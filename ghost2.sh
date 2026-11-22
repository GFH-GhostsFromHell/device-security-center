#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

w(){ mkdir -p "$(dirname "$1")"; cat > "$1"; }

w portal/src/main/java/com/ztsec/ghost/portal/config/SecurityConfig.java <<'EOF'
package com.ztsec.ghost.portal.config;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.core.userdetails.User;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.provisioning.InMemoryUserDetailsManager;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.csrf.CookieCsrfTokenRepository;

/** API chain uses basic auth with a readable CSRF cookie; pages chain uses form login. */
@Configuration
@EnableWebSecurity
public class SecurityConfig {
    private static final int MIN_PASSWORD = 12;

    @Bean
    PasswordEncoder passwordEncoder() { return new BCryptPasswordEncoder(); }

    @Bean
    UserDetailsService users(
            @Value("${ZT_OPERATOR_USERNAME:}") String operator,
            @Value("${ZT_OPERATOR_PASSWORD:}") String operatorPassword,
            @Value("${ZT_ASSET_USERNAME:}") String asset,
            @Value("${ZT_ASSET_PASSWORD:}") String assetPassword) {

        if (operator.isBlank() || asset.isBlank()) {
            throw new IllegalStateException("ZT_OPERATOR_USERNAME and ZT_ASSET_USERNAME are required.");
        }
        if (operatorPassword.length() < MIN_PASSWORD || assetPassword.length() < MIN_PASSWORD) {
            throw new IllegalStateException("Passwords must be at least " + MIN_PASSWORD + " characters.");
        }
        if (operatorPassword.equals(assetPassword)) {
            throw new IllegalStateException("Operator and asset passwords must differ.");
        }

        PasswordEncoder encoder = passwordEncoder();
        return new InMemoryUserDetailsManager(
                User.withUsername(operator).password(encoder.encode(operatorPassword)).roles("OPERATOR").build(),
                User.withUsername(asset).password(encoder.encode(assetPassword)).roles("ASSET").build());
    }

    @Bean
    SecurityFilterChain apiChain(HttpSecurity http) throws Exception {
        http.securityMatcher("/api/zt01/**")
                .csrf(csrf -> csrf.csrfTokenRepository(CookieCsrfTokenRepository.withHttpOnlyFalse()))
                .headers(headers -> headers
                        .contentTypeOptions(Customizer.withDefaults())
                        .frameOptions(Customizer.withDefaults())
                        .httpStrictTransportSecurity(Customizer.withDefaults()))
                .authorizeHttpRequests(auth -> auth.anyRequest().authenticated())
                .httpBasic(Customizer.withDefaults());
        return http.build();
    }

    @Bean
    SecurityFilterChain pageChain(HttpSecurity http) throws Exception {
        http.authorizeHttpRequests(auth -> auth
                        .requestMatchers("/", "/ghost.html", "/takeover.html", "/zt01.css",
                                "/takeover.js", "/comms.js", "/vault.js", "/login",
                                "/actuator/health").permitAll()
                        .anyRequest().authenticated())
                .formLogin(Customizer.withDefaults())
                .logout(Customizer.withDefaults())
                .headers(headers -> headers
                        .contentTypeOptions(Customizer.withDefaults())
                        .frameOptions(Customizer.withDefaults()));
        return http.build();
    }
}
EOF

w portal/src/main/java/com/ztsec/ghost/portal/ops/ChainWatcher.java <<'EOF'
package com.ztsec.ghost.portal.ops;

import org.springframework.stereotype.Component;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Optional;

/** Reads testnet state from a public explorer. */
@Component
public class ChainWatcher {
    private static final String BASE = "https://mempool.space/testnet/api";
    private static final HttpClient CLIENT = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10)).build();

    public Optional<Integer> confirmations(String txid) {
        if (txid == null || !txid.matches("[0-9a-fA-F]{64}")) return Optional.empty();
        try {
            Optional<String> status = get("/tx/" + txid + "/status");
            if (status.isEmpty() || !status.get().contains("\"confirmed\":true")) return Optional.of(0);
            Optional<String> body = get("/tx/" + txid);
            Optional<String> tip = get("/blocks/tip/height");
            if (body.isEmpty() || tip.isEmpty()) return Optional.empty();
            int blockHeight = readInt(body.get(), "\"block_height\":");
            int tipHeight = Integer.parseInt(tip.get().trim());
            if (blockHeight <= 0 || tipHeight <= 0) return Optional.empty();
            return Optional.of(Math.max(1, tipHeight - blockHeight + 1));
        } catch (IOException | InterruptedException | NumberFormatException e) {
            if (e instanceof InterruptedException) Thread.currentThread().interrupt();
            return Optional.empty();
        }
    }

    private Optional<String> get(String path) throws IOException, InterruptedException {
        HttpRequest request = HttpRequest.newBuilder(URI.create(BASE + path))
                .timeout(Duration.ofSeconds(15)).header("Accept", "application/json").GET().build();
        HttpResponse<String> response = CLIENT.send(request, HttpResponse.BodyHandlers.ofString());
        if (response.statusCode() != 200) return Optional.empty();
        return Optional.of(response.body());
    }

    private static int readInt(String json, String key) {
        int at = json.indexOf(key);
        if (at < 0) return -1;
        int cursor = at + key.length();
        StringBuilder digits = new StringBuilder();
        while (cursor < json.length() && Character.isDigit(json.charAt(cursor))) digits.append(json.charAt(cursor++));
        return digits.isEmpty() ? -1 : Integer.parseInt(digits.toString());
    }
}
EOF

w portal/src/main/java/com/ztsec/ghost/portal/ops/CaseController.java <<'EOF'
package com.ztsec.ghost.portal.ops;

import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.sql.Timestamp;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.*;

/** Case creation, pricing and payment claims. Amounts are integer satoshis. */
@RestController
@RequestMapping("/api/zt01/case")
public class CaseController {
    private static final int REQUIRED_CONFIRMATIONS = 2;
    private final JdbcTemplate jdbc;
    private final ChainWatcher chain;

    public CaseController(JdbcTemplate jdbc, ChainWatcher chain) {
        this.jdbc = jdbc;
        this.chain = chain;
    }

    record CaseInput(String label, Integer windowHours, Long priceSats, String address) { }

    record ClaimInput(String method, String reference, Long amountSats) { }

    @PostMapping
    public Map<String, Object> create(@RequestBody CaseInput input, Authentication auth) {
        String label = input.label() == null || input.label().isBlank() ? "unnamed" : input.label().trim();
        int hours = input.windowHours() == null ? 24 : Math.max(1, Math.min(720, input.windowHours()));
        long price = input.priceSats() == null ? 0 : Math.max(0, input.priceSats());
        String address = input.address() == null ? "" : input.address().trim();
        String caseId = UUID.randomUUID().toString().replace("-", "").substring(0, 12).toUpperCase();

        jdbc.update("""
                insert into zt_case (case_id, owner, label, state, price_sats, pay_address, window_hours,
                                     created_at, deadline_at)
                values (?, ?, ?, 'ARMED', ?, ?, ?, ?, ?)
                """, caseId, auth.getName(), label, price, address, hours,
                Timestamp.from(Instant.now()), Timestamp.from(Instant.now().plus(hours, ChronoUnit.HOURS)));

        audit(auth.getName(), "case.create", caseId, label);
        return view(caseId, auth);
    }

    @GetMapping("/{caseId}")
    public Map<String, Object> get(@PathVariable String caseId, Authentication auth) {
        return view(caseId, auth);
    }

    @PostMapping("/{caseId}/claim")
    public Map<String, Object> claim(@PathVariable String caseId, @RequestBody ClaimInput input,
                                     Authentication auth) {
        require(caseId, auth);
        String method = input.method() == null ? "giftcard" : input.method().toLowerCase(Locale.ROOT);
        if (!method.equals("btc") && !method.equals("giftcard")) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "method must be btc or giftcard");
        }
        String reference = input.reference() == null ? "" : input.reference().trim();
        if (method.equals("btc") && !reference.matches("[0-9a-fA-F]{64}")) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "btc reference must be a txid");
        }
        if (method.equals("giftcard") && reference.length() < 6) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "gift card code looks too short");
        }

        long amount = input.amountSats() == null ? 0 : Math.max(0, input.amountSats());
        jdbc.update("insert into zt_claim (case_id, method, reference, amount_sats, created_at) values (?, ?, ?, ?, ?)",
                caseId, method, reference, amount, Timestamp.from(Instant.now()));
        jdbc.update("update zt_case set state = 'PAID' where case_id = ? and state = 'SEALED'", caseId);
        audit(auth.getName(), "case.claim", caseId, method + " " + reference);
        return view(caseId, auth);
    }

    @PostMapping("/{caseId}/verify")
    public Map<String, Object> verify(@PathVariable String caseId, Authentication auth) {
        operator(auth);
        List<Map<String, Object>> claims = jdbc.queryForList(
                "select claim_id, method, reference from zt_claim where case_id = ? and verified = false", caseId);
        if (claims.isEmpty()) throw new ResponseStatusException(HttpStatus.NOT_FOUND, "no open claim");

        for (Map<String, Object> claim : claims) {
            long claimId = ((Number) claim.get("claim_id")).longValue();
            String method = String.valueOf(claim.get("method"));
            int confirmations = method.equals("btc")
                    ? chain.confirmations(String.valueOf(claim.get("reference"))).orElse(0) : 0;
            boolean verified = method.equals("giftcard") || confirmations >= REQUIRED_CONFIRMATIONS;
            jdbc.update("update zt_claim set confirmations = ?, verified = ? where claim_id = ?",
                    confirmations, verified, claimId);
            if (verified) {
                jdbc.update("update zt_case set state = 'PAID', settled_at = ? where case_id = ?",
                        Timestamp.from(Instant.now()), caseId);
            }
            audit(auth.getName(), "case.verify", caseId, method + " conf=" + confirmations + " ok=" + verified);
        }
        return view(caseId, auth);
    }

    private Map<String, Object> view(String caseId, Authentication auth) {
        Map<String, Object> row = require(caseId, auth);
        Map<String, Object> out = new LinkedHashMap<>(row);
        out.put("claims", jdbc.queryForList(
                "select method, reference, amount_sats, confirmations, verified, created_at from zt_claim where case_id = ? order by claim_id",
                caseId));
        out.put("requiredConfirmations", REQUIRED_CONFIRMATIONS);
        return out;
    }

    private Map<String, Object> require(String caseId, Authentication auth) {
        List<Map<String, Object>> rows = jdbc.queryForList("select * from zt_case where case_id = ?", caseId);
        if (rows.isEmpty()) throw new ResponseStatusException(HttpStatus.NOT_FOUND, "unknown case");
        Map<String, Object> row = rows.get(0);
        boolean operator = auth.getAuthorities().stream()
                .anyMatch(a -> a.getAuthority().equals("ROLE_OPERATOR"));
        if (!operator && !String.valueOf(row.get("owner")).equals(auth.getName())) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN, "not your case");
        }
        return row;
    }

    private void operator(Authentication auth) {
        boolean operator = auth.getAuthorities().stream()
                .anyMatch(a -> a.getAuthority().equals("ROLE_OPERATOR"));
        if (!operator) throw new ResponseStatusException(HttpStatus.FORBIDDEN, "operator only");
    }

    private void audit(String actor, String action, String subject, String detail) {
        jdbc.update("insert into zt_audit (actor, action, subject, detail, at) values (?, ?, ?, ?, ?)",
                actor, action, subject, detail.length() > 400 ? detail.substring(0, 400) : detail,
                Timestamp.from(Instant.now()));
    }
}
EOF

w portal/src/main/java/com/ztsec/ghost/portal/ops/ReleaseController.java <<'EOF'
package com.ztsec.ghost.portal.ops;

import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.sql.Timestamp;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.Map;

/** Approval carries its own window and is burned once it closes. */
@RestController
@RequestMapping("/api/zt01/release")
public class ReleaseController {
    private final JdbcTemplate jdbc;

    public ReleaseController(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    record ApproveInput(String wrappedKey, Integer windowMinutes) { }

    @PostMapping("/{caseId}")
    public Map<String, Object> approve(@PathVariable String caseId, @RequestBody ApproveInput input,
                                       Authentication auth) {
        operator(auth);
        Map<String, Object> row = requireCase(caseId);
        if (!"PAID".equals(row.get("state")) && !"SEALED".equals(row.get("state"))) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "case is " + row.get("state"));
        }
        if (input.wrappedKey() == null || input.wrappedKey().isBlank()) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "wrappedKey is required");
        }

        int minutes = input.windowMinutes() == null ? 15 : Math.max(1, Math.min(1440, input.windowMinutes()));
        Instant now = Instant.now();

        jdbc.update("update zt_release set burned = true where case_id = ? and fetched_at is null", caseId);
        jdbc.update("insert into zt_release (case_id, wrapped_key, approved_by, approved_at, expires_at) values (?, ?, ?, ?, ?)",
                caseId, input.wrappedKey(), auth.getName(), Timestamp.from(now),
                Timestamp.from(now.plus(minutes, ChronoUnit.MINUTES)));
        jdbc.update("update zt_case set state = 'RELEASED' where case_id = ?", caseId);
        audit(auth.getName(), "release.approve", caseId, minutes + "m");
        return Map.of("caseId", caseId, "windowMinutes", minutes);
    }

    @GetMapping("/{caseId}")
    public Map<String, Object> fetch(@PathVariable String caseId, Authentication auth) {
        requireCase(caseId);
        List<Map<String, Object>> rows = jdbc.queryForList("""
                select release_id, wrapped_key, expires_at, burned, fetched_at
                from zt_release where case_id = ? order by release_id desc
                """, caseId);
        if (rows.isEmpty()) throw new ResponseStatusException(HttpStatus.NOT_FOUND, "nothing approved");

        Map<String, Object> row = rows.get(0);
        if (Boolean.TRUE.equals(row.get("burned"))) {
            throw new ResponseStatusException(HttpStatus.GONE, "approval was superseded");
        }
        Timestamp expires = (Timestamp) row.get("expires_at");
        if (expires.toInstant().isBefore(Instant.now())) {
            jdbc.update("update zt_release set burned = true where release_id = ?", row.get("release_id"));
            throw new ResponseStatusException(HttpStatus.GONE, "window closed");
        }
        jdbc.update("update zt_release set fetched_at = ? where release_id = ?",
                Timestamp.from(Instant.now()), row.get("release_id"));
        audit(auth.getName(), "release.fetch", caseId, "");
        return Map.of("caseId", caseId, "wrappedKey", row.get("wrapped_key"), "expiresAt", expires.toString());
    }

    private Map<String, Object> requireCase(String caseId) {
        List<Map<String, Object>> rows = jdbc.queryForList("select * from zt_case where case_id = ?", caseId);
        if (rows.isEmpty()) throw new ResponseStatusException(HttpStatus.NOT_FOUND, "unknown case");
        return rows.get(0);
    }

    private void operator(Authentication auth) {
        boolean operator = auth.getAuthorities().stream()
                .anyMatch(a -> a.getAuthority().equals("ROLE_OPERATOR"));
        if (!operator) throw new ResponseStatusException(HttpStatus.FORBIDDEN, "operator only");
    }

    private void audit(String actor, String action, String subject, String detail) {
        jdbc.update("insert into zt_audit (actor, action, subject, detail, at) values (?, ?, ?, ?, ?)",
                actor, action, subject, detail, Timestamp.from(Instant.now()));
    }
}
EOF

w portal/src/main/resources/db/V2__zt01.sql <<'EOF'
create table if not exists zt_case (
    case_id      varchar(32)  primary key,
    owner        varchar(120) not null,
    label        varchar(200) not null,
    state        varchar(16)  not null,
    price_sats   bigint       not null default 0,
    pay_address  varchar(120) not null default '',
    window_hours int          not null default 24,
    file_count   int          not null default 0,
    total_bytes  bigint       not null default 0,
    created_at   timestamp    not null,
    deadline_at  timestamp    null,
    settled_at   timestamp    null
);

create index if not exists zt_case_owner_idx on zt_case (owner);

create table if not exists zt_claim (
    claim_id      bigint generated by default as identity primary key,
    case_id       varchar(32)  not null references zt_case (case_id) on delete cascade,
    method        varchar(16)  not null,
    reference     varchar(160) not null,
    amount_sats   bigint       not null,
    confirmations int          not null default 0,
    verified      boolean      not null default false,
    created_at    timestamp    not null
);

create index if not exists zt_claim_case_idx on zt_claim (case_id);

create table if not exists zt_release (
    release_id  bigint generated by default as identity primary key,
    case_id     varchar(32)  not null references zt_case (case_id) on delete cascade,
    wrapped_key varchar(200) not null,
    approved_by varchar(120) not null,
    approved_at timestamp    not null,
    expires_at  timestamp    not null,
    burned      boolean      not null default false,
    fetched_at  timestamp    null
);

create index if not exists zt_release_case_idx on zt_release (case_id);

create table if not exists zt_audit (
    audit_id bigint generated by default as identity primary key,
    actor    varchar(120) not null,
    action   varchar(64)  not null,
    subject  varchar(120) not null default '',
    detail   varchar(400) not null default '',
    at       timestamp    not null
);
EOF

echo "portal java written"

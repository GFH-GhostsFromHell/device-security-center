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

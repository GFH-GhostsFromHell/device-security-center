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

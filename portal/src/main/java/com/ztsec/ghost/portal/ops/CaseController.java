package com.ztsec.ghost.portal.ops;

import org.springframework.http.HttpStatus;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.security.core.Authentication;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.sql.Timestamp;
import java.time.Instant;
import java.time.format.DateTimeParseException;
import java.time.temporal.ChronoUnit;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Case registration and lookup. A case id is meant to be shareable. */
@RestController
@RequestMapping("/api/zt01/case")
public class CaseController {
    private final JdbcTemplate jdbc;

    public CaseController(JdbcTemplate jdbc) { this.jdbc = jdbc; }

    record CaseInput(String caseId, String label, String deadline, String amount,
                     String address, String fileCount, String bytes) { }

    @PostMapping
    public Map<String, Object> create(@RequestBody CaseInput input, Authentication auth) {
        String caseId = trim(input.caseId());
        if (caseId.isEmpty() || caseId.length() > 32) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "caseId is required");
        }
        Instant deadline = parseDeadline(input.deadline());
        Instant now = Instant.now();

        String label = clip(trim(input.label()), 200);
        String address = clip(trim(input.address()), 120);
        long priceSats = digits(input.amount());
        int fileCount = (int) Math.min(Integer.MAX_VALUE, digits(input.fileCount()));
        long totalBytes = digits(input.bytes());
        int windowHours = (int) Math.max(1, Math.min(8760,
                ChronoUnit.HOURS.between(now, deadline)));

        jdbc.update("""
                insert into zt_case (case_id, owner, label, state, price_sats, pay_address,
                                     window_hours, file_count, total_bytes, created_at, deadline_at)
                values (?, ?, ?, 'SEALED', ?, ?, ?, ?, ?, ?, ?)
                on conflict (case_id) do nothing
                """, caseId, auth.getName(), label, priceSats, address,
                windowHours, fileCount, totalBytes, Timestamp.from(now), Timestamp.from(deadline));

        audit(auth.getName(), "case.create", caseId, fileCount + " files");
        return Map.of("caseId", caseId, "state", "SEALED");
    }

    @GetMapping("/{caseId}")
    public Map<String, Object> fetch(@PathVariable String caseId) {
        List<Map<String, Object>> rows = jdbc.queryForList(
                "select * from zt_case where case_id = ?", caseId);
        if (rows.isEmpty()) throw new ResponseStatusException(HttpStatus.NOT_FOUND, "unknown case");
        Map<String, Object> row = rows.get(0);

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("caseId", row.get("case_id"));
        out.put("label", row.get("label"));
        out.put("state", row.get("state"));
        out.put("amount", row.get("price_sats") + " sats");
        out.put("address", row.get("pay_address"));
        out.put("fileCount", row.get("file_count"));
        out.put("bytes", row.get("total_bytes"));
        out.put("createdAt", String.valueOf(row.get("created_at")));
        out.put("deadline", String.valueOf(row.get("deadline_at")));
        out.put("windowHours", row.get("window_hours"));
        return out;
    }

    private static String trim(String value) { return value == null ? "" : value.trim(); }

    private static String clip(String value, int max) {
        return value.length() <= max ? value : value.substring(0, max);
    }

    private static long digits(String value) {
        if (value == null) return 0;
        StringBuilder out = new StringBuilder();
        for (char c : value.toCharArray()) if (Character.isDigit(c)) out.append(c);
        if (out.isEmpty()) return 0;
        try {
            return Long.parseLong(out.toString());
        } catch (NumberFormatException e) {
            return 0;
        }
    }

    private static Instant parseDeadline(String value) {
        try {
            return Instant.parse(value.trim());
        } catch (DateTimeParseException | NullPointerException e) {
            throw new ResponseStatusException(HttpStatus.BAD_REQUEST, "deadline must be an ISO instant");
        }
    }

    private void audit(String actor, String action, String subject, String detail) {
        jdbc.update("insert into zt_audit (actor, action, subject, detail, at) values (?, ?, ?, ?, ?)",
                actor, action, subject, detail, Timestamp.from(Instant.now()));
    }
}

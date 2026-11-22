package com.ztsec.ghost;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** Durable per-case record. Fields in .zt01.case.json, journal in .zt01.case.log. */
public final class CaseLedger {
    public static final String FIELDS = ".zt01.case.json";
    public static final String JOURNAL = ".zt01.case.log";
    private static final int MAX_JOURNAL_LINES = 2000;

    private final Path fieldsFile;
    private final Path journalFile;
    private final Map<String, String> fields = new LinkedHashMap<>();

    private CaseLedger(Path root) {
        this.fieldsFile = root.resolve(FIELDS);
        this.journalFile = root.resolve(JOURNAL);
    }

    public static CaseLedger create(Path root, String caseId, String label) throws IOException {
        CaseLedger ledger = new CaseLedger(root);
        ledger.fields.put("caseId", caseId);
        ledger.fields.put("root", root.toAbsolutePath().toString());
        ledger.fields.put("label", label == null ? "" : label);
        ledger.fields.put("state", CaseState.DRAFT.name());
        ledger.fields.put("createdAt", Instant.now().toString());
        ledger.fields.put("fileCount", "0");
        ledger.fields.put("bytes", "0");
        ledger.journal("created");
        ledger.save();
        return ledger;
    }

    public static CaseLedger load(Path fieldsFile) throws IOException {
        CaseLedger ledger = new CaseLedger(fieldsFile.getParent());
        for (String line : Files.readAllLines(fieldsFile, StandardCharsets.UTF_8)) {
            String trimmed = line.trim();
            if (!trimmed.startsWith("\"") || !trimmed.contains("\":")) continue;
            int split = trimmed.indexOf("\":");
            String key = trimmed.substring(1, split);
            String value = trimmed.substring(split + 2).trim();
            if (value.endsWith(",")) value = value.substring(0, value.length() - 1);
            if (value.startsWith("\"") && value.endsWith("\"") && value.length() >= 2) {
                value = value.substring(1, value.length() - 1);
            }
            ledger.fields.put(key, value);
        }
        return ledger;
    }

    public static Path locate(Path root) {
        Path candidate = root.resolve(FIELDS);
        return Files.isRegularFile(candidate) ? candidate : null;
    }

    public String get(String key) { return fields.get(key); }

    public String get(String key, String fallback) {
        String value = fields.get(key);
        return value == null || value.isBlank() ? fallback : value;
    }

    public void put(String key, String value) { fields.put(key, value == null ? "" : value); }

    public void put(String key, long value) { fields.put(key, Long.toString(value)); }

    public CaseState state() {
        try {
            return CaseState.valueOf(get("state", CaseState.DRAFT.name()));
        } catch (IllegalArgumentException e) {
            return CaseState.DRAFT;
        }
    }

    public void state(CaseState next) throws IOException {
        journal("state " + state() + " -> " + next);
        fields.put("state", next.name());
        save();
    }

    public String caseId() { return get("caseId", ""); }

    public Path root() { return Path.of(get("root", ".")); }

    public List<String> journalLines() {
        if (!Files.isRegularFile(journalFile)) return List.of();
        try {
            List<String> lines = Files.readAllLines(journalFile, StandardCharsets.UTF_8);
            return new ArrayList<>(lines.subList(Math.max(0, lines.size() - 60), lines.size()));
        } catch (IOException e) {
            return List.of();
        }
    }

    public void journal(String event) {
        try {
            Files.writeString(journalFile, Instant.now() + "  " + event + System.lineSeparator(),
                    StandardCharsets.UTF_8, StandardOpenOption.CREATE, StandardOpenOption.APPEND);
            trimJournal();
        } catch (IOException ignored) {
            // journalling must never abort a run
        }
    }

    private void trimJournal() throws IOException {
        List<String> lines = Files.readAllLines(journalFile, StandardCharsets.UTF_8);
        if (lines.size() <= MAX_JOURNAL_LINES) return;
        Files.write(journalFile, lines.subList(lines.size() - MAX_JOURNAL_LINES, lines.size()),
                StandardCharsets.UTF_8);
    }

    public void save() throws IOException {
        StringBuilder out = new StringBuilder("{\n");
        int index = 0;
        for (Map.Entry<String, String> entry : fields.entrySet()) {
            out.append("  \"").append(entry.getKey()).append("\": \"")
                    .append(entry.getValue().replace("\\", "\\\\").replace("\"", "\\\""))
                    .append("\"");
            if (++index < fields.size()) out.append(',');
            out.append('\n');
        }
        out.append("}\n");
        Files.writeString(fieldsFile, out.toString(), StandardCharsets.UTF_8);
    }
}

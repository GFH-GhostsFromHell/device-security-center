#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

D=ghost-protocol-desktop/src/main/java/com/ztsec/ghost
w(){ mkdir -p "$(dirname "$1")"; cat > "$1"; }

w "$D/CaseLedger.java" <<'EOF'
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
EOF

w "$D/NoticeFile.java" <<'EOF'
package com.ztsec.ghost;

import java.awt.Desktop;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;

/** Drops the human-readable notice into the root and opens it. */
public final class NoticeFile {
    public static final String NAME = "ZT-01_NOTICE.html";

    private NoticeFile() { }

    public static Path write(Path root, String caseId, int fileCount, long bytes,
                             Duration remaining, String price, String address) throws IOException {
        String body = """
                <!doctype html>
                <html lang="en"><head><meta charset="utf-8"><title>ZT-01 // %s</title>
                <style>
                  body{margin:0;min-height:100vh;display:grid;place-items:center;background:#0b0d10;
                       color:#d7dbe0;font:15px/1.6 ui-monospace,Consolas,monospace}
                  main{max-width:640px;padding:40px;border:1px solid #232a33;border-radius:6px;background:#0f1216}
                  h1{margin:0 0 4px;font-size:13px;letter-spacing:.28em;color:#E23A3A;text-transform:uppercase}
                  h2{margin:0 0 24px;font-size:22px}
                  dl{display:grid;grid-template-columns:auto 1fr;gap:8px 20px;margin:0 0 24px;font-size:13px}
                  dt{color:#7d8894;font-size:11px;letter-spacing:.1em;text-transform:uppercase;padding-top:3px}
                  dd{margin:0}
                  .big{font-size:26px;color:#E23A3A}
                  code{background:#171c22;padding:2px 6px;border-radius:3px;font-size:12px;word-break:break-all}
                  footer{color:#6d7883;font-size:11.5px;border-top:1px solid #232a33;padding-top:14px}
                </style></head><body><main>
                  <h1>Project ZT-01 · Zero Trust Security Division</h1>
                  <h2>Files on this device are sealed.</h2>
                  <dl>
                    <dt>Case</dt><dd><code>%s</code></dd>
                    <dt>Files</dt><dd>%d</dd>
                    <dt>Volume</dt><dd>%.1f MB</dd>
                    <dt>Window</dt><dd class="big">%s</dd>
                    <dt>Amount</dt><dd>%s</dd>
                    <dt>Address</dt><dd><code>%s</code></dd>
                  </dl>
                  <p>Each sealed file carries a .zt01 suffix and an authenticated header holding its
                  original name. The master recovery code restores them offline.</p>
                  <footer>The recovery code is shown once at seal time. Store it off this machine.</footer>
                </main></body></html>
                """.formatted(caseId, caseId, fileCount, bytes / 1_048_576.0,
                Countdown.format(remaining), price, address);

        Path notice = root.resolve(NAME);
        Files.writeString(notice, body, StandardCharsets.UTF_8);
        open(notice);
        return notice;
    }

    public static void open(Path file) {
        try {
            if (Desktop.isDesktopSupported()) Desktop.getDesktop().browse(file.toUri());
        } catch (IOException | UnsupportedOperationException ignored) {
            // the caller still has the path
        }
    }
}
EOF

w "$D/WallpaperArt.java" <<'EOF'
package com.ztsec.ghost;

import java.awt.BasicStroke;
import java.awt.Color;
import java.awt.Font;
import java.awt.Graphics2D;
import java.awt.GradientPaint;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.time.Duration;

/** Renders the takeover wallpaper. */
public final class WallpaperArt {
    private static final Color ACCENT = new Color(0xE2, 0x3A, 0x3A);
    private static final Color INK = new Color(0xD7, 0xDB, 0xE0);
    private static final Color MUTE = new Color(0x6D, 0x78, 0x83);

    private WallpaperArt() { }

    public static BufferedImage render(int width, int height, String caseId, Duration remaining) {
        BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
        Graphics2D g = image.createGraphics();
        try {
            g.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING, RenderingHints.VALUE_TEXT_ANTIALIAS_ON);
            g.setPaint(new GradientPaint(0, 0, new Color(0x08, 0x0A, 0x0C), 0, height, new Color(0x11, 0x15, 0x1A)));
            g.fillRect(0, 0, width, height);

            int unit = Math.max(24, width / 48);
            g.setColor(new Color(0x1B, 0x21, 0x28));
            g.setStroke(new BasicStroke(1f));
            for (int x = unit; x < width; x += unit * 2) g.drawLine(x, 0, x, height);
            for (int y = unit; y < height; y += unit * 2) g.drawLine(0, y, width, y);

            int centre = width / 2;
            g.setFont(new Font(Font.MONOSPACED, Font.PLAIN, Math.max(14, unit / 2)));
            g.setColor(ACCENT);
            drawCentred(g, "PROJECT ZT-01  //  OPERATION REDACTED", centre, height / 2 - unit * 4);

            g.setFont(new Font(Font.MONOSPACED, Font.BOLD, Math.max(64, unit * 3)));
            g.setColor(INK);
            drawCentred(g, Countdown.format(remaining), centre, height / 2);

            g.setFont(new Font(Font.MONOSPACED, Font.PLAIN, Math.max(14, unit / 2)));
            g.setColor(MUTE);
            drawCentred(g, "CASE " + caseId, centre, height / 2 + unit * 2);
            drawCentred(g, "ZT-01_NOTICE.html / recovery code required", centre, height / 2 + unit * 3);

            g.setColor(ACCENT);
            g.fillRect(centre - unit * 4, height / 2 - unit * 5, unit * 8, 2);
        } finally {
            g.dispose();
        }
        return image;
    }

    private static void drawCentred(Graphics2D g, String text, int centre, int y) {
        g.drawString(text, centre - g.getFontMetrics().stringWidth(text) / 2, y);
    }
}
EOF

w "$D/Wallpaper.java" <<'EOF'
package com.ztsec.ghost;

import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.List;
import java.util.concurrent.TimeUnit;

/** Swaps the desktop wallpaper and can put the original back. Windows only. */
public final class Wallpaper {
    private static final Path STATE = Path.of(System.getProperty("user.home"), ".zt01-wallpaper");

    private Wallpaper() { }

    public static boolean supported() {
        return System.getProperty("os.name", "").toLowerCase().contains("win");
    }

    public static Path install(Path cacheDir, String caseId, Duration remaining, int width, int height)
            throws IOException {
        if (!supported()) return null;
        Files.createDirectories(cacheDir);

        if (!Files.exists(STATE)) {
            String current = readCurrent();
            if (current != null && !current.isBlank()) Files.writeString(STATE, current, StandardCharsets.UTF_8);
        }

        Path art = cacheDir.resolve("zt01-" + caseId + ".png");
        BufferedImage image = WallpaperArt.render(Math.max(1024, width), Math.max(640, height), caseId, remaining);
        ImageIO.write(image, "png", art.toFile());
        apply(art);
        return art;
    }

    public static void restore() {
        if (!supported() || !Files.isRegularFile(STATE)) return;
        try {
            String original = Files.readString(STATE, StandardCharsets.UTF_8).trim();
            if (!original.isBlank()) apply(Path.of(original));
            Files.deleteIfExists(STATE);
        } catch (IOException ignored) {
            // best effort
        }
    }

    private static String readCurrent() {
        for (String line : run("reg", "query", "HKCU\\Control Panel\\Desktop", "/v", "Wallpaper")) {
            if (line.contains("Wallpaper")) {
                String[] parts = line.trim().split("\\s{2,}");
                if (parts.length >= 3) return parts[parts.length - 1];
            }
        }
        return null;
    }

    private static void apply(Path image) {
        String path = image.toAbsolutePath().toString();
        run("reg", "add", "HKCU\\Control Panel\\Desktop", "/v", "Wallpaper", "/t", "REG_SZ", "/d", path, "/f");
        run("reg", "add", "HKCU\\Control Panel\\Desktop", "/v", "WallpaperStyle", "/t", "REG_SZ", "/d", "10", "/f");
        run("reg", "add", "HKCU\\Control Panel\\Desktop", "/v", "TileWallpaper", "/t", "REG_SZ", "/d", "0", "/f");
        run("rundll32.exe", "user32.dll,UpdatePerUserSystemParameters", "1", "True");
    }

    private static List<String> run(String... command) {
        try {
            Process process = new ProcessBuilder(command).redirectErrorStream(true).start();
            String text = new String(process.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
            process.waitFor(10, TimeUnit.SECONDS);
            return List.of(text.split("\\R"));
        } catch (IOException | InterruptedException e) {
            if (e instanceof InterruptedException) Thread.currentThread().interrupt();
            return List.of();
        }
    }
}
EOF

w "$D/GhostProtocolDesktop.java" <<'EOF'
package com.ztsec.ghost;

import javafx.animation.KeyFrame;
import javafx.animation.Timeline;
import javafx.application.Application;
import javafx.geometry.Insets;
import javafx.geometry.Pos;
import javafx.scene.Scene;
import javafx.scene.control.Label;
import javafx.scene.control.Tab;
import javafx.scene.control.TabPane;
import javafx.scene.layout.BorderPane;
import javafx.scene.layout.HBox;
import javafx.scene.layout.Priority;
import javafx.scene.layout.Region;
import javafx.scene.layout.StackPane;
import javafx.stage.Stage;
import javafx.util.Duration;

import java.time.Instant;

/** Shell. Calm console normally, full-screen takeover once a case is live. */
public final class GhostProtocolDesktop extends Application {
    private Stage stage;
    private TakeoverView takeover;
    private Label modeLabel;
    private final Timeline clock = new Timeline();

    @Override
    public void start(Stage stage) {
        this.stage = stage;
        SweepPanel sweep = new SweepPanel(this::takeOver);
        takeover = new TakeoverView(this::standDown);

        StackPane root = new StackPane(console(sweep), takeover);
        takeover.setVisible(false);
        takeover.setManaged(false);

        Scene scene = new Scene(root, 1080, 720);
        scene.setFill(javafx.scene.paint.Color.web(Theme.BG));
        stage.setScene(scene);
        stage.setTitle("GHOST PROTOCOL // PROJECT ZT-01");
        stage.show();

        clock.getKeyFrames().add(new KeyFrame(Duration.seconds(1), e -> takeover.tick()));
        clock.setCycleCount(Timeline.INDEFINITE);
        clock.play();
    }

    private BorderPane console(SweepPanel sweep) {
        BorderPane pane = new BorderPane();
        Theme.chrome(pane);

        Label mark = new Label("ZT-01");
        mark.setStyle("-fx-text-fill: " + Theme.ACCENT_HEX
                + "; -fx-font-family: 'monospace'; -fx-font-size: 13px; -fx-font-weight: bold;");
        Label division = new Label("ZERO TRUST SECURITY DIVISION");
        Theme.caption(division);

        Region gap = new Region();
        HBox.setHgrow(gap, Priority.ALWAYS);
        modeLabel = new Label("STANDBY");
        Theme.caption(modeLabel);

        HBox bar = new HBox(12, mark, division, gap, modeLabel);
        bar.setAlignment(Pos.CENTER_LEFT);
        bar.setPadding(new Insets(14, 20, 14, 20));
        bar.setStyle("-fx-border-color: " + Theme.LINE + "; -fx-border-width: 0 0 1 0;");
        pane.setTop(bar);

        TabPane tabs = new TabPane();
        tabs.setTabClosingPolicy(TabPane.TabClosingPolicy.UNAVAILABLE);
        tabs.setStyle("-fx-background-color: " + Theme.BG + ";");
        tabs.getTabs().addAll(
                new Tab("SWEEP", sweep),
                new Tab("VAULT", new VaultPanel()),
                new Tab("RECOVERY", new RecoveryPanel()),
                new Tab("COMMS", new CommsPanel()));
        pane.setCenter(tabs);

        Label footer = new Label("AES-256-GCM  /  per-file data keys  /  master recovery code");
        Theme.caption(footer);
        footer.setPadding(new Insets(10, 20, 10, 20));
        pane.setBottom(footer);

        return pane;
    }

    private void takeOver(String[] details) {
        takeover.arm(details[0], details[1], details[2], ArmTimer.until(Instant.parse(details[4])));
        takeover.setVisible(true);
        takeover.setManaged(true);
        takeover.toFront();
        modeLabel.setText("LIVE");
        modeLabel.setStyle("-fx-text-fill: " + Theme.ACCENT_HEX
                + "; -fx-font-family: 'monospace'; -fx-font-size: 10.5px;");
        stage.setFullScreen(true);
        stage.setFullScreenExitHint("Esc releases full screen");
    }

    private void standDown() {
        takeover.setVisible(false);
        takeover.setManaged(false);
        modeLabel.setText("STANDBY");
        Theme.caption(modeLabel);
        stage.setFullScreen(false);
    }

    @Override
    public void stop() {
        clock.stop();
    }
}
EOF

rm -f ghost.sh ghost2.sh ghost2b.sh ghost3.sh ghost4.sh ghost5.sh ghost6.sh fix1.sh fix2.sh
git add -A
git status --short | wc -l
git commit -q -m "fix: repair tree structure, add missing desktop sources"
git push -u origin ghost-protocol
echo DONE

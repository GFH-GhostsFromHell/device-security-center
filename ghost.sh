#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
[ "$(git branch --show-current)" = "ghost-protocol" ] || { echo "not on ghost-protocol"; exit 1; }

git rm -q \
  device-security-desktop/src/main/java/com/gfh/devicesecurity/DeviceSecurityDesktop.java \
  portal/src/main/java/com/example/remoteportal/config/SecurityConfig.java \
  portal/src/main/resources/static/device-security.html \
  portal/src/main/resources/static/device-security-chat.js \
  portal/src/main/resources/static/device-security-escrow.js

w(){ mkdir -p "$(dirname "$1")"; cat > "$1"; }

w ghost-protocol-desktop/src/main/java/com/ztsec/ghost/MasterKey.java <<'EOF'
package com.ztsec.ghost;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;
import java.util.Arrays;
import java.util.Base64;
import java.util.zip.CRC32;

/** Protocol master key. Per-file data keys are wrapped with this key. */
public final class MasterKey {
    private static final int KEY_BYTES = 32;
    private static final int NONCE_BYTES = 12;
    private static final int TAG_BITS = 128;
    private static final SecureRandom RNG = new SecureRandom();

    private final SecretKey key;

    private MasterKey(byte[] raw) { this.key = new SecretKeySpec(raw, "AES"); }

    public static MasterKey generate() throws GeneralSecurityException {
        KeyGenerator generator = KeyGenerator.getInstance("AES");
        generator.init(256, RNG);
        return new MasterKey(generator.generateKey().getEncoded());
    }

    /** base64url(key || crc32(key)); the checksum catches a mistyped character. */
    public String recoveryCode() {
        byte[] raw = key.getEncoded();
        byte[] code = Arrays.copyOf(raw, raw.length + 4);
        System.arraycopy(checksum(raw), 0, code, raw.length, 4);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(code);
    }

    public static MasterKey fromRecoveryCode(String code) {
        byte[] decoded;
        try {
            decoded = Base64.getUrlDecoder().decode(code.trim());
        } catch (IllegalArgumentException e) {
            throw new IllegalArgumentException("Recovery code is not valid base64url.");
        }
        if (decoded.length != KEY_BYTES + 4) throw new IllegalArgumentException("Wrong code length.");
        byte[] raw = Arrays.copyOf(decoded, KEY_BYTES);
        byte[] given = Arrays.copyOfRange(decoded, KEY_BYTES, KEY_BYTES + 4);
        if (!Arrays.equals(given, checksum(raw))) throw new IllegalArgumentException("Checksum mismatch.");
        return new MasterKey(raw);
    }

    /** Output is nonce || ciphertext || tag. */
    public byte[] wrap(SecretKey dataKey, byte[] aad) throws GeneralSecurityException {
        byte[] nonce = new byte[NONCE_BYTES];
        RNG.nextBytes(nonce);
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, key, new GCMParameterSpec(TAG_BITS, nonce));
        cipher.updateAAD(aad);
        byte[] sealed = cipher.doFinal(dataKey.getEncoded());
        byte[] out = Arrays.copyOf(nonce, NONCE_BYTES + sealed.length);
        System.arraycopy(sealed, 0, out, NONCE_BYTES, sealed.length);
        return out;
    }

    public SecretKey unwrap(byte[] blob, byte[] aad) throws GeneralSecurityException {
        if (blob.length <= NONCE_BYTES) throw new GeneralSecurityException("Wrapped key is truncated.");
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE, key, new GCMParameterSpec(TAG_BITS, blob, 0, NONCE_BYTES));
        cipher.updateAAD(aad);
        return new SecretKeySpec(cipher.doFinal(blob, NONCE_BYTES, blob.length - NONCE_BYTES), "AES");
    }

    private static byte[] checksum(byte[] raw) {
        CRC32 crc = new CRC32();
        crc.update(raw);
        long value = crc.getValue();
        return new byte[]{(byte) (value >>> 24), (byte) (value >>> 16), (byte) (value >>> 8), (byte) value};
    }
}
EOF

w ghost-protocol-desktop/src/main/java/com/ztsec/ghost/SealedFormat.java <<'EOF'
package com.ztsec.ghost;

import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

/** magic(8) version(1) flags(1) reserved(2) nonce(12) wrappedKey(60) nameLen(2) name(n) payload. */
public final class SealedFormat {
    public static final byte[] MAGIC = "ZTPROTO1".getBytes(StandardCharsets.US_ASCII);
    public static final byte VERSION = 2;
    public static final byte FLAG_ORIGINAL_DELETED = 1;
    public static final String EXTENSION = ".zt01";

    public static final int NONCE_OFFSET = 12;
    public static final int WRAPPED_KEY_OFFSET = NONCE_OFFSET + 12;
    public static final int WRAPPED_KEY_LENGTH = 60;
    public static final int NAME_LENGTH_OFFSET = WRAPPED_KEY_OFFSET + WRAPPED_KEY_LENGTH;
    public static final int NAME_OFFSET = NAME_LENGTH_OFFSET + 2;

    private final String originalName;
    private final byte flags;
    private final byte[] nonce;
    private final byte[] wrappedKey;
    private final byte[] header;

    public SealedFormat(String originalName, byte flags, byte[] nonce, byte[] wrappedKey) {
        if (originalName == null || originalName.isBlank()) throw new IllegalArgumentException("Name required.");
        if (nonce.length != 12) throw new IllegalArgumentException("Nonce must be 12 bytes.");
        if (wrappedKey.length != WRAPPED_KEY_LENGTH) throw new IllegalArgumentException("Key must be 60 bytes.");
        this.originalName = originalName;
        this.flags = flags;
        this.nonce = nonce;
        this.wrappedKey = wrappedKey;
        byte[] name = originalName.getBytes(StandardCharsets.UTF_8);
        this.header = ByteBuffer.allocate(NAME_OFFSET + name.length)
                .put(MAGIC).put(VERSION).put(flags).putShort((short) 0)
                .put(nonce).put(wrappedKey).putShort((short) name.length).put(name)
                .array();
    }

    public byte[] header() { return header.clone(); }
    public int headerLength() { return header.length; }
    public byte[] nonce() { return nonce.clone(); }
    public byte[] wrappedKey() { return wrappedKey.clone(); }
    public String originalName() { return originalName; }
    public byte flags() { return flags; }

    public byte[] aad() { return aad(originalName, flags); }

    public static byte[] aad(String name, byte flags) {
        byte[] raw = name.getBytes(StandardCharsets.UTF_8);
        return ByteBuffer.allocate(12 + raw.length)
                .put(MAGIC).put(VERSION).put(flags).putShort((short) 0)
                .putShort((short) raw.length).put(raw)
                .array();
    }

    public static boolean isSealed(byte[] head) {
        if (head.length < MAGIC.length) return false;
        return Arrays.equals(head, 0, MAGIC.length, MAGIC, 0, MAGIC.length);
    }

    public static SealedFormat parse(byte[] head) {
        if (!isSealed(head)) throw new IllegalArgumentException("Not sealed.");
        if (head.length < NAME_OFFSET) throw new IllegalArgumentException("Truncated.");
        if (head[8] != VERSION) throw new IllegalArgumentException("Bad version.");
        byte flags = head[9];
        byte[] nonce = Arrays.copyOfRange(head, NONCE_OFFSET, NONCE_OFFSET + 12);
        byte[] wrapped = Arrays.copyOfRange(head, WRAPPED_KEY_OFFSET, WRAPPED_KEY_OFFSET + WRAPPED_KEY_LENGTH);
        int length = ((head[NAME_LENGTH_OFFSET] & 0xff) << 8) | (head[NAME_LENGTH_OFFSET + 1] & 0xff);
        if (length == 0 || head.length < NAME_OFFSET + length) throw new IllegalArgumentException("Bad name.");
        return new SealedFormat(new String(head, NAME_OFFSET, length, StandardCharsets.UTF_8), flags, nonce, wrapped);
    }
}
EOF

w ghost-protocol-desktop/src/main/java/com/ztsec/ghost/Seal.java <<'EOF'
package com.ztsec.ghost;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;
import java.util.Set;
import java.util.function.BiConsumer;
import java.util.stream.Stream;

/** Plan, seal, verify, and only then remove the original. */
public final class Seal {
    public static final Set<String> SKIP_DIRS = Set.of(
            ".git", "node_modules", "target", "build", "dist", ".venv", "__pycache__",
            "$RECYCLE.BIN", "System Volume Information", ".idea", ".gradle");
    public static final long MAX_BYTES = 64L * 1024 * 1024;

    private static final SecureRandom RNG = new SecureRandom();
    private static final int TAG_BITS = 128;
    private static final int BUFFER = 64 * 1024;

    public record Candidate(Path path, long size) { }

    public record Plan(List<Candidate> files, long bytes, List<String> skipped) { }

    public Plan plan(Path root) throws IOException {
        if (!Files.isDirectory(root)) throw new IOException("Not a folder: " + root);
        List<Candidate> files = new ArrayList<>();
        List<String> skipped = new ArrayList<>();
        long bytes = 0;
        try (Stream<Path> walk = Files.walk(root)) {
            for (Path path : (Iterable<Path>) walk.sorted(Comparator.naturalOrder())::iterator) {
                if (Files.isDirectory(path)) continue;
                String rel = root.relativize(path).toString();
                if (inSkippedFolder(root, path)) { skipped.add(rel); continue; }
                long size = Files.size(path);
                if (size == 0 || size > MAX_BYTES || isSealed(path)) { skipped.add(rel); continue; }
                files.add(new Candidate(path, size));
                bytes += size;
            }
        }
        return new Plan(List.copyOf(files), bytes, List.copyOf(skipped));
    }

    public void seal(Plan plan, MasterKey master, BiConsumer<Integer, Integer> progress)
            throws IOException, GeneralSecurityException {
        int done = 0;
        int total = plan.files().size();
        for (Candidate candidate : plan.files()) {
            sealOne(candidate.path(), master);
            done++;
            progress.accept(done, total);
        }
    }

    private void sealOne(Path file, MasterKey master) throws IOException, GeneralSecurityException {
        String name = file.getFileName().toString();
        byte flags = SealedFormat.FLAG_ORIGINAL_DELETED;

        KeyGenerator generator = KeyGenerator.getInstance("AES");
        generator.init(256, RNG);
        SecretKey dataKey = generator.generateKey();

        byte[] aad = SealedFormat.aad(name, flags);
        byte[] wrapped = master.wrap(dataKey, aad);
        byte[] nonce = new byte[12];
        RNG.nextBytes(nonce);

        SealedFormat format = new SealedFormat(name, flags, nonce, wrapped);
        Path temp = file.resolveSibling(name + ".part");

        try (InputStream in = Files.newInputStream(file);
             OutputStream out = Files.newOutputStream(temp,
                     StandardOpenOption.CREATE, StandardOpenOption.TRUNCATE_EXISTING, StandardOpenOption.WRITE)) {
            out.write(format.header());
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, dataKey, new GCMParameterSpec(TAG_BITS, nonce));
            cipher.updateAAD(format.aad());
            byte[] buffer = new byte[BUFFER];
            int read;
            while ((read = in.read(buffer)) > 0) out.write(cipher.update(buffer, 0, read));
            out.write(cipher.doFinal());
        }

        long expected = Files.size(file);
        if (verify(temp, master, expected) != expected) {
            Files.deleteIfExists(temp);
            throw new IOException("Verification failed for " + name);
        }

        Files.delete(file);
        Files.move(temp, file.resolveSibling(name + SealedFormat.EXTENSION));
    }

    public static long verify(Path sealed, MasterKey master, long expected)
            throws IOException, GeneralSecurityException {
        try (InputStream in = Files.newInputStream(sealed)) {
            byte[] head = in.readNBytes(SealedFormat.NAME_OFFSET + 512);
            SealedFormat format = SealedFormat.parse(head);
            SecretKey dataKey = master.unwrap(format.wrappedKey(), format.aad());
            in.skipNBytes((long) format.headerLength() - head.length);

            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, dataKey, new GCMParameterSpec(TAG_BITS, format.nonce()));
            cipher.updateAAD(format.aad());

            long total = 0;
            byte[] buffer = new byte[BUFFER];
            int read;
            while ((read = in.read(buffer)) > 0) total += cipher.update(buffer, 0, read).length;
            total += cipher.doFinal().length;
            if (total != expected) throw new IOException("Recovered " + total + " of " + expected);
            return total;
        }
    }

    public static Path unseal(Path sealed, MasterKey master, Path targetDirectory)
            throws IOException, GeneralSecurityException {
        try (InputStream in = Files.newInputStream(sealed)) {
            byte[] head = in.readNBytes(SealedFormat.NAME_OFFSET + 512);
            SealedFormat format = SealedFormat.parse(head);
            in.skipNBytes((long) format.headerLength() - head.length);

            SecretKey dataKey = master.unwrap(format.wrappedKey(), format.aad());
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, dataKey, new GCMParameterSpec(TAG_BITS, format.nonce()));
            cipher.updateAAD(format.aad());

            Path target = targetDirectory.resolve(format.originalName());
            try (OutputStream out = Files.newOutputStream(target,
                    StandardOpenOption.CREATE, StandardOpenOption.TRUNCATE_EXISTING, StandardOpenOption.WRITE)) {
                byte[] buffer = new byte[BUFFER];
                int read;
                while ((read = in.read(buffer)) > 0) out.write(cipher.update(buffer, 0, read));
                out.write(cipher.doFinal());
            }
            return target;
        }
    }

    private static boolean inSkippedFolder(Path root, Path path) {
        for (Path part : root.relativize(path)) if (SKIP_DIRS.contains(part.toString())) return true;
        return false;
    }

    public static boolean isSealed(Path path) {
        try (InputStream in = Files.newInputStream(path)) {
            return SealedFormat.isSealed(in.readNBytes(SealedFormat.MAGIC.length));
        } catch (IOException e) {
            return false;
        }
    }
}
EOF

w ghost-protocol-desktop/src/main/java/com/ztsec/ghost/FileVault.java <<'EOF'
package com.ztsec.ghost;

import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;

/** Single-file seal and open. */
public final class FileVault {
    private static final SecureRandom RNG = new SecureRandom();
    private static final int TAG_BITS = 128;
    private static final int BUFFER = 64 * 1024;

    public Path seal(Path source, Path destination, MasterKey master)
            throws IOException, GeneralSecurityException {
        String name = source.getFileName().toString();
        byte flags = 0;

        KeyGenerator generator = KeyGenerator.getInstance("AES");
        generator.init(256, RNG);
        SecretKey dataKey = generator.generateKey();

        byte[] aad = SealedFormat.aad(name, flags);
        byte[] wrapped = master.wrap(dataKey, aad);
        byte[] nonce = new byte[12];
        RNG.nextBytes(nonce);
        SealedFormat format = new SealedFormat(name, flags, nonce, wrapped);

        try (InputStream in = Files.newInputStream(source);
             OutputStream out = Files.newOutputStream(destination,
                     StandardOpenOption.CREATE, StandardOpenOption.TRUNCATE_EXISTING, StandardOpenOption.WRITE)) {
            out.write(format.header());
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.ENCRYPT_MODE, dataKey, new GCMParameterSpec(TAG_BITS, nonce));
            cipher.updateAAD(format.aad());
            byte[] buffer = new byte[BUFFER];
            int read;
            while ((read = in.read(buffer)) > 0) out.write(cipher.update(buffer, 0, read));
            out.write(cipher.doFinal());
        }
        return destination;
    }

    public Path open(Path sealed, Path destination, MasterKey master)
            throws IOException, GeneralSecurityException {
        try (InputStream in = Files.newInputStream(sealed)) {
            byte[] head = in.readNBytes(SealedFormat.NAME_OFFSET + 512);
            SealedFormat format = SealedFormat.parse(head);
            in.skipNBytes((long) format.headerLength() - head.length);

            SecretKey dataKey = master.unwrap(format.wrappedKey(), format.aad());
            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(Cipher.DECRYPT_MODE, dataKey, new GCMParameterSpec(TAG_BITS, format.nonce()));
            cipher.updateAAD(format.aad());

            try (OutputStream out = Files.newOutputStream(destination,
                    StandardOpenOption.CREATE, StandardOpenOption.TRUNCATE_EXISTING, StandardOpenOption.WRITE)) {
                byte[] buffer = new byte[BUFFER];
                int read;
                while ((read = in.read(buffer)) > 0) out.write(cipher.update(buffer, 0, read));
                out.write(cipher.doFinal());
            }
        }
        return destination;
    }

    public String originalName(Path sealed) throws IOException {
        try (InputStream in = Files.newInputStream(sealed)) {
            return SealedFormat.parse(in.readNBytes(SealedFormat.NAME_OFFSET + 512)).originalName();
        }
    }
}
EOF

w ghost-protocol-desktop/src/main/java/com/ztsec/ghost/CaseState.java <<'EOF'
package com.ztsec.ghost;

/** Lifecycle of one collection run. */
public enum CaseState {
    DRAFT,
    ARMED,
    SEALED,
    PAID,
    RELEASED,
    EXPIRED;

    public boolean isTerminal() { return this == RELEASED || this == EXPIRED; }

    public boolean canSeal() { return this == ARMED || this == DRAFT; }
}
EOF

w ghost-protocol-desktop/src/main/java/com/ztsec/ghost/ArmTimer.java <<'EOF'
package com.ztsec.ghost;

import java.time.Duration;
import java.time.Instant;

/** Deadline arithmetic. The deadline is stored, never counted down. */
public final class ArmTimer {
    private final Instant deadline;

    private ArmTimer(Instant deadline) { this.deadline = deadline; }

    public static ArmTimer until(Instant deadline) { return new ArmTimer(deadline); }

    public static ArmTimer hoursFromNow(int hours) {
        return new ArmTimer(Instant.now().plus(Duration.ofHours(Math.max(1, hours))));
    }

    public Instant deadline() { return deadline; }

    public Duration remaining() {
        Duration left = Duration.between(Instant.now(), deadline);
        return left.isNegative() ? Duration.ZERO : left;
    }

    public boolean expired() { return !Instant.now().isBefore(deadline); }
}
EOF

w ghost-protocol-desktop/src/main/java/com/ztsec/ghost/Countdown.java <<'EOF'
package com.ztsec.ghost;

import java.time.Duration;

/** Zero-padded clock text. */
public final class Countdown {
    private Countdown() { }

    public static String format(Duration duration) {
        long total = Math.max(0, duration.toSeconds());
        long days = total / 86_400;
        long hours = (total % 86_400) / 3_600;
        long minutes = (total % 3_600) / 60;
        long seconds = total % 60;
        if (days > 0) return String.format("%d:%02d:%02d:%02d", days, hours, minutes, seconds);
        return String.format("%02d:%02d:%02d", hours, minutes, seconds);
    }
}
EOF

w ghost-protocol-desktop/src/main/java/com/ztsec/ghost/Theme.java <<'EOF'
package com.ztsec.ghost;

import javafx.scene.control.Button;
import javafx.scene.control.Label;
import javafx.scene.layout.Region;

/** Shared palette. */
public final class Theme {
    public static final String ACCENT_HEX = "#E23A3A";
    public static final String BG = "#0B0D10";
    public static final String PANEL = "#0F1216";
    public static final String LINE = "#232A33";
    public static final String INK = "#D7DBE0";
    public static final String MUTE = "#7D8894";

    private Theme() { }

    public static void chrome(Region region) { region.setStyle("-fx-background-color: " + BG + ";"); }

    public static void caption(Label label) {
        label.setStyle("-fx-text-fill: " + MUTE + "; -fx-font-family: 'monospace'; -fx-font-size: 10.5px;");
    }

    public static void primary(Button button) {
        button.setStyle("-fx-background-color: " + ACCENT_HEX + "; -fx-text-fill: white;"
                + " -fx-font-family: 'monospace'; -fx-font-size: 12px; -fx-padding: 9 18;"
                + " -fx-background-radius: 3; -fx-cursor: hand;");
    }

    public static void secondary(Button button) {
        button.setStyle("-fx-background-color: " + PANEL + "; -fx-text-fill: " + INK + ";"
                + " -fx-border-color: " + LINE + "; -fx-border-radius: 3; -fx-background-radius: 3;"
                + " -fx-font-family: 'monospace'; -fx-font-size: 12px; -fx-padding: 9 18; -fx-cursor: hand;");
    }
}
EOF

w ghost-protocol-desktop/src/main/java/com/ztsec/ghost/TakeoverView.java <<'EOF'
package com.ztsec.ghost;

import javafx.geometry.Insets;
import javafx.geometry.Pos;
import javafx.scene.control.Button;
import javafx.scene.control.Label;
import javafx.scene.input.Clipboard;
import javafx.scene.input.ClipboardContent;
import javafx.scene.layout.Region;
import javafx.scene.layout.VBox;

/** Full-screen state. The clock is the hero. */
public final class TakeoverView extends VBox {
    private final Label clockText = new Label("00:00:00");
    private final Label caseText = new Label();
    private final Label amountText = new Label();
    private final Label addressText = new Label();
    private final Label progressText = new Label();
    private ArmTimer timer;

    public TakeoverView(Runnable onExit) {
        Theme.chrome(this);
        setAlignment(Pos.CENTER);
        setSpacing(10);
        setPadding(new Insets(60));

        Label eyebrow = new Label("PROJECT ZT-01  //  OPERATION REDACTED");
        eyebrow.setStyle("-fx-text-fill: " + Theme.ACCENT_HEX + "; -fx-font-family: 'monospace'; -fx-font-size: 12px;");

        Label headline = new Label("Files on this device are sealed.");
        headline.setStyle("-fx-text-fill: " + Theme.INK
                + "; -fx-font-family: 'monospace'; -fx-font-size: 26px; -fx-font-weight: bold;");

        clockText.setStyle("-fx-text-fill: " + Theme.INK
                + "; -fx-font-family: 'monospace'; -fx-font-size: 96px; -fx-font-weight: bold;");
        caseText.setStyle("-fx-text-fill: " + Theme.MUTE + "; -fx-font-family: 'monospace'; -fx-font-size: 12px;");
        amountText.setStyle("-fx-text-fill: " + Theme.ACCENT_HEX + "; -fx-font-family: 'monospace'; -fx-font-size: 20px;");

        addressText.setStyle("-fx-text-fill: " + Theme.INK
                + "; -fx-font-family: 'monospace'; -fx-font-size: 12px; -fx-wrap-text: true;"
                + " -fx-background-color: " + Theme.PANEL + "; -fx-border-color: " + Theme.LINE
                + "; -fx-border-radius: 3; -fx-background-radius: 3; -fx-padding: 10 14;");
        addressText.setMaxWidth(560);
        addressText.setAlignment(Pos.CENTER);

        Button copy = new Button("COPY ADDRESS");
        Theme.secondary(copy);
        copy.setOnAction(e -> {
            ClipboardContent content = new ClipboardContent();
            content.putString(addressText.getText());
            Clipboard.getSystemClipboard().setContent(content);
            copy.setText("COPIED");
        });

        progressText.setStyle("-fx-text-fill: " + Theme.MUTE + "; -fx-font-family: 'monospace'; -fx-font-size: 11px;");

        Button restore = new Button("RESTORE");
        Theme.primary(restore);
        Button exit = new Button("EXIT TAKEOVER");
        Theme.secondary(exit);
        exit.setOnAction(e -> onExit.run());

        Region hair = new Region();
        hair.setPrefSize(120, 2);
        hair.setStyle("-fx-background-color: " + Theme.ACCENT_HEX + ";");
        Region spacer = new Region();
        spacer.setPrefHeight(18);

        getChildren().addAll(eyebrow, headline, hair, clockText, caseText, spacer,
                amountText, addressText, copy, progressText, spacer, restore, exit);
    }

    public void arm(String caseId, String amount, String address, ArmTimer timer) {
        this.timer = timer;
        caseText.setText("CASE " + caseId);
        amountText.setText(amount);
        addressText.setText(address);
        tick();
    }

    public void tick() {
        if (timer == null) return;
        clockText.setText(Countdown.format(timer.remaining()));
        progressText.setText(timer.expired() ? "WINDOW CLOSED" : "WINDOW OPEN");
    }
}
EOF

w ghost-protocol-desktop/src/main/java/com/ztsec/ghost/SweepPanel.java <<'EOF'
package com.ztsec.ghost;

import javafx.geometry.Insets;
import javafx.geometry.Pos;
import javafx.scene.control.Button;
import javafx.scene.control.Label;
import javafx.scene.control.TextField;
import javafx.scene.layout.HBox;
import javafx.scene.layout.Priority;
import javafx.scene.layout.Region;
import javafx.scene.layout.VBox;
import javafx.stage.DirectoryChooser;

import java.io.File;
import java.nio.file.Path;
import java.util.UUID;
import java.util.function.Consumer;

/** Pre-lockdown console: pick a root, preview the pass, arm and seal. */
public final class SweepPanel extends VBox {
    private final TextField rootField = new TextField();
    private final TextField hoursField = new TextField("24");
    private final TextField priceField = new TextField("150000 sats");
    private final TextField addressField = new TextField("bc1q-address-here");
    private final Label preview = new Label("No folder selected.");
    private final Button seal = new Button("SEAL");
    private final Label status = new Label();
    private final Consumer<String[]> onArm;

    public SweepPanel(Consumer<String[]> onArm) {
        this.onArm = onArm;
        setPadding(new Insets(24));
        setSpacing(14);

        Label title = new Label("SWEEP");
        title.setStyle("-fx-text-fill: " + Theme.INK
                + "; -fx-font-family: 'monospace'; -fx-font-size: 16px; -fx-font-weight: bold;");
        Label sub = new Label("Originals are removed only after the sealed copy verifies.");
        Theme.caption(sub);

        rootField.setPromptText("C:\\path\\to\\folder");
        rootField.setStyle("-fx-background-color: " + Theme.PANEL + "; -fx-text-fill: " + Theme.INK
                + "; -fx-border-color: " + Theme.LINE + "; -fx-font-family: 'monospace'; -fx-padding: 9;");
        HBox.setHgrow(rootField, Priority.ALWAYS);

        Button browse = new Button("BROWSE");
        Theme.secondary(browse);
        browse.setOnAction(e -> {
            DirectoryChooser chooser = new DirectoryChooser();
            File chosen = chooser.showDialog(getScene().getWindow());
            if (chosen != null) {
                rootField.setText(chosen.getAbsolutePath());
                plan(Path.of(chosen.getAbsolutePath()));
            }
        });

        HBox rootRow = new HBox(10, rootField, browse);
        rootRow.setAlignment(Pos.CENTER_LEFT);

        HBox options = new HBox(10,
                field("WINDOW (HOURS)", hoursField),
                field("AMOUNT", priceField),
                field("ADDRESS", addressField));

        preview.setStyle("-fx-text-fill: " + Theme.MUTE + "; -fx-font-family: 'monospace'; -fx-font-size: 12px;");

        Theme.primary(seal);
        seal.setDisable(true);
        seal.setOnAction(e -> runSeal());

        status.setStyle("-fx-text-fill: " + Theme.MUTE + "; -fx-font-family: 'monospace'; -fx-font-size: 12px;");
        status.setWrapText(true);

        Region grow = new Region();
        VBox.setVgrow(grow, Priority.ALWAYS);

        getChildren().addAll(title, sub, rootRow, options, preview, seal, status, grow);
    }

    private VBox field(String caption, TextField input) {
        Label label = new Label(caption);
        Theme.caption(label);
        input.setStyle("-fx-background-color: " + Theme.PANEL + "; -fx-text-fill: " + Theme.INK
                + "; -fx-border-color: " + Theme.LINE + "; -fx-font-family: 'monospace'; -fx-padding: 9;");
        VBox box = new VBox(6, label, input);
        HBox.setHgrow(box, Priority.ALWAYS);
        return box;
    }

    private void plan(Path root) {
        try {
            Seal.Plan plan = new Seal().plan(root);
            preview.setText(plan.files().size() + " files, " + (plan.bytes() / 1_048_576)
                    + " MB, " + plan.skipped().size() + " skipped");
            seal.setDisable(plan.files().isEmpty());
        } catch (Exception e) {
            preview.setText(e.getMessage());
            seal.setDisable(true);
        }
    }

    private void runSeal() {
        Path root = Path.of(rootField.getText().trim());
        int hours = Math.max(1, Integer.parseInt(hoursField.getText().trim().replaceAll("\\D", "")));
        String amount = priceField.getText().trim();
        String address = addressField.getText().trim();
        String caseId = UUID.randomUUID().toString().substring(0, 8).toUpperCase();

        seal.setDisable(true);
        status.setText("sealing...");

        Thread worker = new Thread(() -> {
            try {
                CaseLedger ledger = CaseLedger.create(root, caseId, root.getFileName().toString());
                ledger.state(CaseState.ARMED);
                ArmTimer timer = ArmTimer.hoursFromNow(hours);
                ledger.put("deadline", timer.deadline().toString());
                ledger.put("amount", amount);
                ledger.put("address", address);
                ledger.save();

                Seal.Plan plan = new Seal().plan(root);
                MasterKey master = MasterKey.generate();
                ledger.put("fileCount", plan.files().size());
                ledger.put("bytes", plan.bytes());
                ledger.state(CaseState.SEALED);

                new Seal().seal(plan, master, (done, total) ->
                        javafx.application.Platform.runLater(() -> status.setText("sealing " + done + "/" + total)));

                String code = master.recoveryCode();
                ledger.put("recoveryCode", code);
                ledger.save();
                NoticeFile.write(root, caseId, plan.files().size(), plan.bytes(), timer.remaining(), amount, address);

                javafx.application.Platform.runLater(() -> {
                    status.setText("sealed. code: " + code);
                    onArm.accept(new String[]{caseId, amount, address, code});
                });
            } catch (Exception e) {
                javafx.application.Platform.runLater(() -> {
                    status.setText("failed: " + e.getMessage());
                    seal.setDisable(false);
                });
            }
        }, "sweep");
        worker.setDaemon(true);
        worker.start();
    }
}
EOF

w ghost-protocol-desktop/src/main/java/com/ztsec/ghost/VaultPanel.java <<'EOF'
package com.ztsec.ghost;

import javafx.geometry.Insets;
import javafx.geometry.Pos;
import javafx.scene.control.Button;
import javafx.scene.control.Label;
import javafx.scene.control.TextField;
import javafx.scene.layout.HBox;
import javafx.scene.layout.VBox;
import javafx.stage.FileChooser;

import java.io.File;
import java.nio.file.Path;

/** Single-file seal and open. */
public final class VaultPanel extends VBox {
    private final TextField codeField = new TextField();
    private final Label status = new Label();

    public VaultPanel() {
        setPadding(new Insets(24));
        setSpacing(14);

        Label title = new Label("VAULT");
        title.setStyle("-fx-text-fill: " + Theme.INK
                + "; -fx-font-family: 'monospace'; -fx-font-size: 16px; -fx-font-weight: bold;");
        Label sub = new Label("One file in, one .zt01 out. The original is left in place.");
        Theme.caption(sub);

        Button make = new Button("SEAL A FILE");
        Theme.primary(make);
        make.setOnAction(e -> sealFile());

        codeField.setPromptText("recovery code");
        codeField.setStyle("-fx-background-color: " + Theme.PANEL + "; -fx-text-fill: " + Theme.INK
                + "; -fx-border-color: " + Theme.LINE + "; -fx-font-family: 'monospace'; -fx-padding: 9;");

        Button open = new Button("OPEN A .zt01");
        Theme.secondary(open);
        open.setOnAction(e -> openFile());

        HBox row = new HBox(10, codeField, open);
        row.setAlignment(Pos.CENTER_LEFT);

        status.setStyle("-fx-text-fill: " + Theme.MUTE + "; -fx-font-family: 'monospace'; -fx-font-size: 12px;");
        status.setWrapText(true);

        getChildren().addAll(title, sub, make, row, status);
    }

    private void sealFile() {
        FileChooser chooser = new FileChooser();
        File source = chooser.showOpenDialog(getScene().getWindow());
        if (source == null) return;
        try {
            Path path = source.toPath();
            Path out = path.resolveSibling(path.getFileName() + SealedFormat.EXTENSION);
            MasterKey master = MasterKey.generate();
            new FileVault().seal(path, out, master);
            status.setText("sealed " + out.getFileName() + "  |  code: " + master.recoveryCode());
        } catch (Exception e) {
            status.setText("failed: " + e.getMessage());
        }
    }

    private void openFile() {
        FileChooser chooser = new FileChooser();
        chooser.getExtensionFilters().add(new FileChooser.ExtensionFilter("Sealed", "*.zt01"));
        File sealed = chooser.showOpenDialog(getScene().getWindow());
        if (sealed == null) return;
        try {
            Path path = sealed.toPath();
            String name = new FileVault().originalName(path);
            new FileVault().open(path, path.resolveSibling(name), MasterKey.fromRecoveryCode(codeField.getText()));
            status.setText("restored " + name);
        } catch (Exception e) {
            status.setText("failed: " + e.getMessage());
        }
    }
}
EOF

w ghost-protocol-desktop/src/main/java/com/ztsec/ghost/RecoveryPanel.java <<'EOF'
package com.ztsec.ghost;

import javafx.geometry.Insets;
import javafx.scene.control.Button;
import javafx.scene.control.Label;
import javafx.scene.control.TextField;
import javafx.scene.layout.HBox;
import javafx.scene.layout.VBox;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.stream.Stream;

/** Bulk recovery from a folder using the master code. */
public final class RecoveryPanel extends VBox {
    private final TextField codeField = new TextField();
    private final TextField rootField = new TextField();
    private final Label status = new Label();

    public RecoveryPanel() {
        setPadding(new Insets(24));
        setSpacing(14);

        Label title = new Label("RECOVERY");
        title.setStyle("-fx-text-fill: " + Theme.INK
                + "; -fx-font-family: 'monospace'; -fx-font-size: 16px; -fx-font-weight: bold;");
        Label sub = new Label("Restores every .zt01 it verifies, leaves the rest.");
        Theme.caption(sub);

        codeField.setPromptText("recovery code");
        rootField.setPromptText("folder containing .zt01 files");
        for (TextField field : List.of(codeField, rootField)) {
            field.setStyle("-fx-background-color: " + Theme.PANEL + "; -fx-text-fill: " + Theme.INK
                    + "; -fx-border-color: " + Theme.LINE + "; -fx-font-family: 'monospace'; -fx-padding: 9;");
        }

        Button run = new Button("RESTORE ALL");
        Theme.primary(run);
        run.setOnAction(e -> restore());

        HBox row = new HBox(10, rootField, run);

        status.setStyle("-fx-text-fill: " + Theme.MUTE + "; -fx-font-family: 'monospace'; -fx-font-size: 12px;");
        status.setWrapText(true);

        getChildren().addAll(title, sub, codeField, row, status);
    }

    private void restore() {
        try {
            Path root = Path.of(rootField.getText().trim());
            MasterKey master = MasterKey.fromRecoveryCode(codeField.getText());
            int ok = 0;
            int failed = 0;
            try (Stream<Path> walk = Files.walk(root)) {
                for (Path path : (Iterable<Path>) walk::iterator) {
                    if (!path.toString().endsWith(SealedFormat.EXTENSION)) continue;
                    try {
                        Seal.unseal(path, master, path.getParent());
                        ok++;
                    } catch (Exception e) {
                        failed++;
                    }
                }
            }
            status.setText(ok + " restored, " + failed + " failed.");
        } catch (Exception e) {
            status.setText("failed: " + e.getMessage());
        }
    }
}
EOF

w ghost-protocol-desktop/src/main/java/com/ztsec/ghost/CommsPanel.java <<'EOF'
package com.ztsec.ghost;

import javafx.geometry.Insets;
import javafx.scene.control.Button;
import javafx.scene.control.Label;
import javafx.scene.control.TextArea;
import javafx.scene.layout.Priority;
import javafx.scene.layout.VBox;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

/** Local running notes. */
public final class CommsPanel extends VBox {
    private static final Path NOTES = Path.of(System.getProperty("user.home"), ".zt01", "comms.log");
    private final TextArea log = new TextArea();

    public CommsPanel() {
        setPadding(new Insets(24));
        setSpacing(12);

        Label title = new Label("COMMS");
        title.setStyle("-fx-text-fill: " + Theme.INK
                + "; -fx-font-family: 'monospace'; -fx-font-size: 16px; -fx-font-weight: bold;");
        Label sub = new Label("Offline journal.");
        Theme.caption(sub);

        log.setStyle("-fx-control-inner-background: " + Theme.PANEL + "; -fx-text-fill: " + Theme.INK
                + "; -fx-font-family: 'monospace'; -fx-font-size: 12px; -fx-border-color: " + Theme.LINE + ";");
        log.setEditable(false);
        VBox.setVgrow(log, Priority.ALWAYS);

        Button clear = new Button("CLEAR");
        Theme.secondary(clear);
        clear.setOnAction(e -> {
            try {
                Files.deleteIfExists(NOTES);
            } catch (Exception ignored) { }
            log.clear();
        });

        getChildren().addAll(title, sub, log, clear);
        load();
    }

    private void load() {
        try {
            if (Files.isRegularFile(NOTES)) log.setText(Files.readString(NOTES, StandardCharsets.UTF_8));
        } catch (Exception e) {
            log.setText("(unreadable: " + e.getMessage() + ")");
        }
    }
}
EOF

w NOTES.md <<'EOF'
# PROJECT ZT-01 / GHOST PROTOCOL — open items

## Not finished

- `SweepPanel` never calls `POST /api/zt01/case`, so a desktop case and a portal case are
  separate records, and the desktop never uploads its wrapped key.
- `GhostProtocolDesktop.takeOver` rebuilds the timer as 24 hours instead of using the one
  the sweep produced, so the takeover clock is wrong for any other window.
- `ghost.html` has no CSRF header handling; the cookie repository is configured but the
  scripts never read `XSRF-TOKEN`.

## Known behaviour

- Sealing deletes the original only after the sealed copy decrypts to the right byte count.
- Skip list: `.git`, `node_modules`, `target`, `build`, `dist`, `.venv`, `__pycache__`,
  `.idea`, `.gradle`, recycle bin, System Volume Information.
- Files over 64 MiB and empty files are skipped and counted.
- Gift card claims are eyeballed by an operator; only BTC gets chain checks, on testnet.
- An approval is burned when its window closes or a newer approval supersedes it.
EOF

echo "desktop half written"

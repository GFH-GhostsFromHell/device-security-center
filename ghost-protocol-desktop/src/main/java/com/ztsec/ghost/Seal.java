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

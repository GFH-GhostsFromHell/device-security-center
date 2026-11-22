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

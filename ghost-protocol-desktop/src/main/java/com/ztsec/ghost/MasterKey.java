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

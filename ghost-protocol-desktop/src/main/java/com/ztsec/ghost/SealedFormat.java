package com.ztsec.ghost;

import java.io.IOException;
import java.io.InputStream;
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
        return ByteBuffer.allocate(MAGIC.length + 6 + raw.length)
                .put(MAGIC).put(VERSION).put(flags).putShort((short) 0)
                .putShort((short) raw.length).put(raw)
                .array();
    }

    public static boolean isSealed(byte[] head) {
        if (head.length < MAGIC.length) return false;
        return Arrays.equals(head, 0, MAGIC.length, MAGIC, 0, MAGIC.length);
    }

    /**
     * Reads exactly one header from a forward-only stream and leaves the stream
     * positioned on the first payload byte.
     */
    public static SealedFormat readHeader(InputStream in) throws IOException {
        byte[] fixed = in.readNBytes(NAME_LENGTH_OFFSET + 2);
        if (fixed.length < NAME_LENGTH_OFFSET + 2) throw new IllegalArgumentException("Truncated.");
        int length = ((fixed[NAME_LENGTH_OFFSET] & 0xff) << 8) | (fixed[NAME_LENGTH_OFFSET + 1] & 0xff);
        if (length == 0) throw new IllegalArgumentException("Bad name.");
        byte[] name = in.readNBytes(length);
        if (name.length != length) throw new IllegalArgumentException("Truncated.");
        byte[] head = Arrays.copyOf(fixed, NAME_OFFSET + length);
        System.arraycopy(name, 0, head, NAME_OFFSET, length);
        return parse(head);
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

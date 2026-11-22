package com.ztsec.ghost;

import org.junit.jupiter.api.Test;

import java.util.Arrays;

import static org.junit.jupiter.api.Assertions.*;

class SealedFormatTest {
    private static SealedFormat sample() {
        return new SealedFormat("report final.docx", (byte) 0, new byte[12], new byte[SealedFormat.WRAPPED_KEY_LENGTH]);
    }

    @Test
    void headerRoundTrips() {
        assertEquals("report final.docx", SealedFormat.parse(sample().header()).originalName());
    }

    @Test
    void magicIsStable() {
        assertEquals("ZTPROTO1", new String(SealedFormat.MAGIC));
        assertTrue(SealedFormat.isSealed(sample().header()));
    }

    @Test
    void truncationIsRejected() {
        byte[] header = sample().header();
        assertThrows(IllegalArgumentException.class,
                () -> SealedFormat.parse(Arrays.copyOf(header, SealedFormat.NAME_OFFSET - 1)));
    }

    @Test
    void aadDiffersPerName() {
        assertFalse(Arrays.equals(SealedFormat.aad("a.txt", (byte) 0), SealedFormat.aad("b.txt", (byte) 0)));
    }
}

package com.ztsec.ghost;

import org.junit.jupiter.api.Test;

import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import java.util.Arrays;

import static org.junit.jupiter.api.Assertions.*;

class MasterKeyTest {
    private static SecretKey dataKey() throws Exception {
        KeyGenerator g = KeyGenerator.getInstance("AES");
        g.init(256);
        return g.generateKey();
    }

    @Test
    void recoveryCodeRoundTrips() throws Exception {
        MasterKey original = MasterKey.generate();
        MasterKey restored = MasterKey.fromRecoveryCode(original.recoveryCode());
        byte[] wrapped = original.wrap(dataKey(), SealedFormat.aad("a.txt", (byte) 0));
        assertNotNull(restored.unwrap(wrapped, SealedFormat.aad("a.txt", (byte) 0)));
    }

    @Test
    void wrongCodeIsRejected() throws Exception {
        String code = MasterKey.generate().recoveryCode();
        String broken = (code.charAt(0) == 'A' ? "B" : "A") + code.substring(1);
        assertThrows(IllegalArgumentException.class, () -> MasterKey.fromRecoveryCode(broken));
    }

    @Test
    void aadMismatchBreaksUnwrap() throws Exception {
        MasterKey key = MasterKey.generate();
        byte[] wrapped = key.wrap(dataKey(), SealedFormat.aad("a.txt", (byte) 0));
        assertThrows(Exception.class, () -> key.unwrap(wrapped, SealedFormat.aad("b.txt", (byte) 0)));
    }

    @Test
    void wrapIsNonDeterministic() throws Exception {
        MasterKey key = MasterKey.generate();
        byte[] aad = SealedFormat.aad("x", (byte) 0);
        assertFalse(Arrays.equals(key.wrap(dataKey(), aad), key.wrap(dataKey(), aad)));
    }
}

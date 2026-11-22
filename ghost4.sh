#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

w(){ mkdir -p "$(dirname "$1")"; cat > "$1"; }

w ghost-protocol-desktop/src/test/java/com/ztsec/ghost/MasterKeyTest.java <<'EOF'
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
    void wrongCodeIsRejected() {
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
EOF

w ghost-protocol-desktop/src/test/java/com/ztsec/ghost/SealedFormatTest.java <<'EOF'
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
EOF

w ghost-protocol-desktop/src/test/java/com/ztsec/ghost/SealTest.java <<'EOF'
package com.ztsec.ghost;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.*;

class SealTest {
    @TempDir
    Path root;

    @Test
    void sealRemovesOriginalAndRecoversExactBytes() throws Exception {
        Path file = root.resolve("note.txt");
        byte[] content = "zero trust".repeat(500).getBytes(StandardCharsets.UTF_8);
        Files.write(file, content);

        MasterKey master = MasterKey.generate();
        Seal seal = new Seal();
        seal.seal(seal.plan(root), master, (done, total) -> { });

        assertFalse(Files.exists(file));
        Path sealed = root.resolve("note.txt" + SealedFormat.EXTENSION);
        assertTrue(Files.exists(sealed));

        Path out = Files.createDirectories(root.resolve("out"));
        assertArrayEquals(content, Files.readAllBytes(Seal.unseal(sealed, master, out)));
    }

    @Test
    void secondPassSkipsSealedFiles() throws Exception {
        Files.write(root.resolve("a.txt"), "one".getBytes(StandardCharsets.UTF_8));
        Seal seal = new Seal();
        seal.seal(seal.plan(root), MasterKey.generate(), (d, t) -> { });
        assertTrue(seal.plan(root).files().isEmpty());
    }

    @Test
    void skippedFoldersAreIgnored() throws Exception {
        Path git = Files.createDirectories(root.resolve(".git"));
        Files.write(git.resolve("HEAD"), "ref".getBytes(StandardCharsets.UTF_8));
        Files.write(root.resolve("real.txt"), "data".getBytes(StandardCharsets.UTF_8));
        assertEquals(1, new Seal().plan(root).files().size());
    }
}
EOF

w ghost-protocol-desktop/src/test/java/com/ztsec/ghost/CaseLedgerTest.java <<'EOF'
package com.ztsec.ghost;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.*;

class CaseLedgerTest {
    @TempDir
    Path root;

    @Test
    void stateSurvivesReload() throws Exception {
        CaseLedger ledger = CaseLedger.create(root, "ABC123", "label");
        ledger.state(CaseState.ARMED);
        CaseLedger reloaded = CaseLedger.load(CaseLedger.locate(root));
        assertEquals(CaseState.ARMED, reloaded.state());
        assertEquals("ABC123", reloaded.caseId());
    }

    @Test
    void unknownStateFallsBackToDraft() throws Exception {
        CaseLedger ledger = CaseLedger.create(root, "ABC123", "label");
        ledger.put("state", "NONSENSE");
        assertEquals(CaseState.DRAFT, CaseLedger.load(CaseLedger.locate(root)).state());
    }
}
EOF

w portal/src/test/java/com/ztsec/ghost/portal/ops/ReleaseControllerTest.java <<'EOF'
package com.ztsec.ghost.portal.ops;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.httpBasic;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest(properties = {
        "ZT_OPERATOR_USERNAME=operator",
        "ZT_OPERATOR_PASSWORD=operator-password-1",
        "ZT_ASSET_USERNAME=asset",
        "ZT_ASSET_PASSWORD=asset-password-12"
})
@AutoConfigureMockMvc
class ReleaseControllerTest {
    @Autowired
    MockMvc mvc;

    @Test
    void approveRequiresOperator() throws Exception {
        mvc.perform(post("/api/zt01/release/MISSING")
                        .with(httpBasic("asset", "asset-password-12"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"wrappedKey\":\"abc\"}"))
                .andExpect(status().isForbidden());
    }

    @Test
    void approveOnUnknownCaseIsNotFound() throws Exception {
        mvc.perform(post("/api/zt01/release/MISSING")
                        .with(httpBasic("operator", "operator-password-1"))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"wrappedKey\":\"abc\"}"))
                .andExpect(status().isNotFound());
    }
}
EOF

mvx(){ [ -e "$1" ] && { mkdir -p "$(dirname "$2")"; git mv --force -- "$1" "$2"; }; }
mvx device-security-desktop ghost-protocol-desktop
mvx ghost-protocol-desktop/src/main/java/com/gfh/devicesecurity ghost-protocol-desktop/src/main/java/com/ztsec/ghost
mvx ghost-protocol-desktop/src/test/java/com/gfh/devicesecurity ghost-protocol-desktop/src/test/java/com/ztsec/ghost
mvx portal/src/main/java/com/example/remoteportal portal/src/main/java/com/ztsec/ghost/portal
mvx portal/src/main/java/com/ztsec/ghost/portal/device portal/src/main/java/com/ztsec/ghost/portal/ops
mvx portal/src/test/java/com/example/remoteportal portal/src/test/java/com/ztsec/ghost/portal
mvx .github/workflows/build-device-security-desktop.yml .github/workflows/build-ghost-protocol-desktop.yml
mvx .github/workflows/build-device-security-portal.yml .github/workflows/build-ghost-protocol-portal.yml
mvx .github/workflows/validate-device-security-web.yml .github/workflows/validate-ghost-protocol-web.yml

grep -rlI --exclude-dir=.git --exclude-dir=target . | while read -r f; do
  sed -i \
    -e 's|com\.gfh\.devicesecurity|com.ztsec.ghost|g' \
    -e 's|com\.example\.remoteportal\.device|com.ztsec.ghost.portal.ops|g' \
    -e 's|com\.example\.remoteportal|com.ztsec.ghost.portal|g' \
    -e 's|device-security-desktop|ghost-protocol-desktop|g' \
    -e 's|/api/device-security|/api/zt01|g' \
    -e 's|device_security_|zt_|g' \
    -e 's|DEVICE_ADMIN_|ZT_OPERATOR_|g' \
    -e 's|DEVICE_CLIENT_|ZT_ASSET_|g' \
    -e 's|ROLE_ADMIN|ROLE_OPERATOR|g' \
    -e 's|ROLE_CLIENT|ROLE_ASSET|g' \
    -e 's|"ADMIN"|"OPERATOR"|g' \
    -e 's|"CLIENT"|"ASSET"|g' \
    -e 's|\.gfhlk|.zt01|g' \
    -e 's|\.gfhenc|.zts|g' \
    -e 's|GFHLOCK1|ZTPROTO1|g' \
    -e 's|Device Security Center|GHOST PROTOCOL|g' \
    -e 's|device security center|GHOST PROTOCOL|g' \
    "$f"
done

find . -name '*DeviceSecurity*' -not -path './.git/*' | while read -r f; do
  base=$(basename "$f" | sed -e 's/DeviceSecurityDesktop/GhostProtocolDesktop/g' -e 's/DeviceSecurityCenter/GhostProtocol/g')
  [ "$base" = "$(basename "$f")" ] || git mv --force -- "$f" "$(dirname "$f")/$base"
done

rm -f ghost.sh ghost2.sh ghost3.sh ghost4.sh
git add -A
git status --short | wc -l
git commit -q -m "feat: GHOST PROTOCOL / PROJECT ZT-01"
git push -u origin ghost-protocol
echo DONE

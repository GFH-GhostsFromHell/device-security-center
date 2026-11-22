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

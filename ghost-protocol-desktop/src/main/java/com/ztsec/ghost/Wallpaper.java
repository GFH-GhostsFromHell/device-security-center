package com.ztsec.ghost;

import javax.imageio.ImageIO;
import java.awt.image.BufferedImage;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.List;
import java.util.concurrent.TimeUnit;

/** Swaps the desktop wallpaper and can put the original back. Windows only. */
public final class Wallpaper {
    private static final Path STATE = Path.of(System.getProperty("user.home"), ".zt01-wallpaper");

    private Wallpaper() { }

    public static boolean supported() {
        return System.getProperty("os.name", "").toLowerCase().contains("win");
    }

    public static Path install(Path cacheDir, String caseId, Duration remaining, int width, int height)
            throws IOException {
        if (!supported()) return null;
        Files.createDirectories(cacheDir);

        if (!Files.exists(STATE)) {
            String current = readCurrent();
            if (current != null && !current.isBlank()) Files.writeString(STATE, current, StandardCharsets.UTF_8);
        }

        Path art = cacheDir.resolve("zt01-" + caseId + ".png");
        BufferedImage image = WallpaperArt.render(Math.max(1024, width), Math.max(640, height), caseId, remaining);
        ImageIO.write(image, "png", art.toFile());
        apply(art);
        return art;
    }

    public static void restore() {
        if (!supported() || !Files.isRegularFile(STATE)) return;
        try {
            String original = Files.readString(STATE, StandardCharsets.UTF_8).trim();
            if (!original.isBlank()) apply(Path.of(original));
            Files.deleteIfExists(STATE);
        } catch (IOException ignored) {
            // best effort
        }
    }

    private static String readCurrent() {
        for (String line : run("reg", "query", "HKCU\\Control Panel\\Desktop", "/v", "Wallpaper")) {
            if (line.contains("Wallpaper")) {
                String[] parts = line.trim().split("\\s{2,}");
                if (parts.length >= 3) return parts[parts.length - 1];
            }
        }
        return null;
    }

    private static void apply(Path image) {
        String path = image.toAbsolutePath().toString();
        run("reg", "add", "HKCU\\Control Panel\\Desktop", "/v", "Wallpaper", "/t", "REG_SZ", "/d", path, "/f");
        run("reg", "add", "HKCU\\Control Panel\\Desktop", "/v", "WallpaperStyle", "/t", "REG_SZ", "/d", "10", "/f");
        run("reg", "add", "HKCU\\Control Panel\\Desktop", "/v", "TileWallpaper", "/t", "REG_SZ", "/d", "0", "/f");
        run("rundll32.exe", "user32.dll,UpdatePerUserSystemParameters", "1", "True");
    }

    private static List<String> run(String... command) {
        try {
            Process process = new ProcessBuilder(command).redirectErrorStream(true).start();
            String text = new String(process.getInputStream().readAllBytes(), StandardCharsets.UTF_8);
            process.waitFor(10, TimeUnit.SECONDS);
            return List.of(text.split("\\R"));
        } catch (IOException | InterruptedException e) {
            if (e instanceof InterruptedException) Thread.currentThread().interrupt();
            return List.of();
        }
    }
}

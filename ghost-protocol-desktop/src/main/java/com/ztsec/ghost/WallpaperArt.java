package com.ztsec.ghost;

import java.awt.BasicStroke;
import java.awt.Color;
import java.awt.Font;
import java.awt.Graphics2D;
import java.awt.GradientPaint;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.time.Duration;

/** Renders the takeover wallpaper. */
public final class WallpaperArt {
    private static final Color ACCENT = new Color(0xE2, 0x3A, 0x3A);
    private static final Color INK = new Color(0xD7, 0xDB, 0xE0);
    private static final Color MUTE = new Color(0x6D, 0x78, 0x83);

    private WallpaperArt() { }

    public static BufferedImage render(int width, int height, String caseId, Duration remaining) {
        BufferedImage image = new BufferedImage(width, height, BufferedImage.TYPE_INT_RGB);
        Graphics2D g = image.createGraphics();
        try {
            g.setRenderingHint(RenderingHints.KEY_TEXT_ANTIALIASING, RenderingHints.VALUE_TEXT_ANTIALIAS_ON);
            g.setPaint(new GradientPaint(0, 0, new Color(0x08, 0x0A, 0x0C), 0, height, new Color(0x11, 0x15, 0x1A)));
            g.fillRect(0, 0, width, height);

            int unit = Math.max(24, width / 48);
            g.setColor(new Color(0x1B, 0x21, 0x28));
            g.setStroke(new BasicStroke(1f));
            for (int x = unit; x < width; x += unit * 2) g.drawLine(x, 0, x, height);
            for (int y = unit; y < height; y += unit * 2) g.drawLine(0, y, width, y);

            int centre = width / 2;
            g.setFont(new Font(Font.MONOSPACED, Font.PLAIN, Math.max(14, unit / 2)));
            g.setColor(ACCENT);
            drawCentred(g, "PROJECT ZT-01  //  OPERATION REDACTED", centre, height / 2 - unit * 4);

            g.setFont(new Font(Font.MONOSPACED, Font.BOLD, Math.max(64, unit * 3)));
            g.setColor(INK);
            drawCentred(g, Countdown.format(remaining), centre, height / 2);

            g.setFont(new Font(Font.MONOSPACED, Font.PLAIN, Math.max(14, unit / 2)));
            g.setColor(MUTE);
            drawCentred(g, "CASE " + caseId, centre, height / 2 + unit * 2);
            drawCentred(g, "ZT-01_NOTICE.html / recovery code required", centre, height / 2 + unit * 3);

            g.setColor(ACCENT);
            g.fillRect(centre - unit * 4, height / 2 - unit * 5, unit * 8, 2);
        } finally {
            g.dispose();
        }
        return image;
    }

    private static void drawCentred(Graphics2D g, String text, int centre, int y) {
        g.drawString(text, centre - g.getFontMetrics().stringWidth(text) / 2, y);
    }
}

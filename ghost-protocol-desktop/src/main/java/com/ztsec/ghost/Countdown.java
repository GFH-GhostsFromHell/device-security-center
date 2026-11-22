package com.ztsec.ghost;

import java.time.Duration;

/** Zero-padded clock text. */
public final class Countdown {
    private Countdown() { }

    public static String format(Duration duration) {
        long total = Math.max(0, duration.toSeconds());
        long days = total / 86_400;
        long hours = (total % 86_400) / 3_600;
        long minutes = (total % 3_600) / 60;
        long seconds = total % 60;
        if (days > 0) return String.format("%d:%02d:%02d:%02d", days, hours, minutes, seconds);
        return String.format("%02d:%02d:%02d", hours, minutes, seconds);
    }
}

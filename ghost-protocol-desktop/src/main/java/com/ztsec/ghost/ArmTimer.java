package com.ztsec.ghost;

import java.time.Duration;
import java.time.Instant;

/** Deadline arithmetic. The deadline is stored, never counted down. */
public final class ArmTimer {
    private final Instant deadline;

    private ArmTimer(Instant deadline) { this.deadline = deadline; }

    public static ArmTimer until(Instant deadline) { return new ArmTimer(deadline); }

    public static ArmTimer hoursFromNow(int hours) {
        return new ArmTimer(Instant.now().plus(Duration.ofHours(Math.max(1, hours))));
    }

    public Instant deadline() { return deadline; }

    public Duration remaining() {
        Duration left = Duration.between(Instant.now(), deadline);
        return left.isNegative() ? Duration.ZERO : left;
    }

    public boolean expired() { return !Instant.now().isBefore(deadline); }
}

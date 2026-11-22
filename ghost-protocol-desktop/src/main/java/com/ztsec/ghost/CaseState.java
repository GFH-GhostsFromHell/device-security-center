package com.ztsec.ghost;

/** Lifecycle of one collection run. */
public enum CaseState {
    DRAFT,
    ARMED,
    SEALED,
    PAID,
    RELEASED,
    EXPIRED;

    public boolean isTerminal() { return this == RELEASED || this == EXPIRED; }

    public boolean canSeal() { return this == ARMED || this == DRAFT; }
}

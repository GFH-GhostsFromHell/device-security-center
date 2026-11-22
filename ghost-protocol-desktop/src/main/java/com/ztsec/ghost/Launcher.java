package com.ztsec.ghost;

/**
 * Separate entry point for classpath-based Windows packaging.
 * Never performs disk modifications.
 */
public final class Launcher {
    private Launcher() { }
    public static void main(String[] args) {
        javafx.application.Application.launch(GhostProtocolDesktop.class, args);
    }
}

package com.ztsec.ghost;

import javafx.scene.control.Button;
import javafx.scene.control.Label;
import javafx.scene.layout.Region;

/** Shared palette. */
public final class Theme {
    public static final String ACCENT_HEX = "#E23A3A";
    public static final String BG = "#0B0D10";
    public static final String PANEL = "#0F1216";
    public static final String LINE = "#232A33";
    public static final String INK = "#D7DBE0";
    public static final String MUTE = "#7D8894";

    private Theme() { }

    public static void chrome(Region region) { region.setStyle("-fx-background-color: " + BG + ";"); }

    public static void caption(Label label) {
        label.setStyle("-fx-text-fill: " + MUTE + "; -fx-font-family: 'monospace'; -fx-font-size: 10.5px;");
    }

    public static void primary(Button button) {
        button.setStyle("-fx-background-color: " + ACCENT_HEX + "; -fx-text-fill: white;"
                + " -fx-font-family: 'monospace'; -fx-font-size: 12px; -fx-padding: 9 18;"
                + " -fx-background-radius: 3; -fx-cursor: hand;");
    }

    public static void secondary(Button button) {
        button.setStyle("-fx-background-color: " + PANEL + "; -fx-text-fill: " + INK + ";"
                + " -fx-border-color: " + LINE + "; -fx-border-radius: 3; -fx-background-radius: 3;"
                + " -fx-font-family: 'monospace'; -fx-font-size: 12px; -fx-padding: 9 18; -fx-cursor: hand;");
    }
}

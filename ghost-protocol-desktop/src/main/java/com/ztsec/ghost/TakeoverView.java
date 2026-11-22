package com.ztsec.ghost;

import javafx.geometry.Insets;
import javafx.geometry.Pos;
import javafx.scene.control.Button;
import javafx.scene.control.Label;
import javafx.scene.input.Clipboard;
import javafx.scene.input.ClipboardContent;
import javafx.scene.layout.Region;
import javafx.scene.layout.VBox;

/** Full-screen state. The clock is the hero. */
public final class TakeoverView extends VBox {
    private final Label clockText = new Label("00:00:00");
    private final Label caseText = new Label();
    private final Label amountText = new Label();
    private final Label addressText = new Label();
    private final Label progressText = new Label();
    private ArmTimer timer;

    public TakeoverView(Runnable onExit) {
        Theme.chrome(this);
        setAlignment(Pos.CENTER);
        setSpacing(10);
        setPadding(new Insets(60));

        Label eyebrow = new Label("PROJECT ZT-01  //  OPERATION REDACTED");
        eyebrow.setStyle("-fx-text-fill: " + Theme.ACCENT_HEX + "; -fx-font-family: 'monospace'; -fx-font-size: 12px;");

        Label headline = new Label("Files on this device are sealed.");
        headline.setStyle("-fx-text-fill: " + Theme.INK
                + "; -fx-font-family: 'monospace'; -fx-font-size: 26px; -fx-font-weight: bold;");

        clockText.setStyle("-fx-text-fill: " + Theme.INK
                + "; -fx-font-family: 'monospace'; -fx-font-size: 96px; -fx-font-weight: bold;");
        caseText.setStyle("-fx-text-fill: " + Theme.MUTE + "; -fx-font-family: 'monospace'; -fx-font-size: 12px;");
        amountText.setStyle("-fx-text-fill: " + Theme.ACCENT_HEX + "; -fx-font-family: 'monospace'; -fx-font-size: 20px;");

        addressText.setStyle("-fx-text-fill: " + Theme.INK
                + "; -fx-font-family: 'monospace'; -fx-font-size: 12px; -fx-wrap-text: true;"
                + " -fx-background-color: " + Theme.PANEL + "; -fx-border-color: " + Theme.LINE
                + "; -fx-border-radius: 3; -fx-background-radius: 3; -fx-padding: 10 14;");
        addressText.setMaxWidth(560);
        addressText.setAlignment(Pos.CENTER);

        Button copy = new Button("COPY ADDRESS");
        Theme.secondary(copy);
        copy.setOnAction(e -> {
            ClipboardContent content = new ClipboardContent();
            content.putString(addressText.getText());
            Clipboard.getSystemClipboard().setContent(content);
            copy.setText("COPIED");
        });

        progressText.setStyle("-fx-text-fill: " + Theme.MUTE + "; -fx-font-family: 'monospace'; -fx-font-size: 11px;");

        Button restore = new Button("RESTORE");
        Theme.primary(restore);
        Button exit = new Button("EXIT TAKEOVER");
        Theme.secondary(exit);
        exit.setOnAction(e -> onExit.run());

        Region hair = new Region();
        hair.setPrefSize(120, 2);
        hair.setStyle("-fx-background-color: " + Theme.ACCENT_HEX + ";");
        Region spacer = new Region();
        spacer.setPrefHeight(18);

        getChildren().addAll(eyebrow, headline, hair, clockText, caseText, spacer,
                amountText, addressText, copy, progressText, spacer, restore, exit);
    }

    public void arm(String caseId, String amount, String address, ArmTimer timer) {
        this.timer = timer;
        caseText.setText("CASE " + caseId);
        amountText.setText(amount);
        addressText.setText(address);
        tick();
    }

    public void tick() {
        if (timer == null) return;
        clockText.setText(Countdown.format(timer.remaining()));
        progressText.setText(timer.expired() ? "WINDOW CLOSED" : "WINDOW OPEN");
    }
}

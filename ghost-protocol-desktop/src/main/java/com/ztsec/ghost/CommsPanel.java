package com.ztsec.ghost;

import javafx.geometry.Insets;
import javafx.scene.control.Button;
import javafx.scene.control.Label;
import javafx.scene.control.TextArea;
import javafx.scene.layout.Priority;
import javafx.scene.layout.VBox;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;

/** Local running notes. */
public final class CommsPanel extends VBox {
    private static final Path NOTES = Path.of(System.getProperty("user.home"), ".zt01", "comms.log");
    private final TextArea log = new TextArea();

    public CommsPanel() {
        setPadding(new Insets(24));
        setSpacing(12);

        Label title = new Label("COMMS");
        title.setStyle("-fx-text-fill: " + Theme.INK
                + "; -fx-font-family: 'monospace'; -fx-font-size: 16px; -fx-font-weight: bold;");
        Label sub = new Label("Offline journal.");
        Theme.caption(sub);

        log.setStyle("-fx-control-inner-background: " + Theme.PANEL + "; -fx-text-fill: " + Theme.INK
                + "; -fx-font-family: 'monospace'; -fx-font-size: 12px; -fx-border-color: " + Theme.LINE + ";");
        log.setEditable(false);
        VBox.setVgrow(log, Priority.ALWAYS);

        Button clear = new Button("CLEAR");
        Theme.secondary(clear);
        clear.setOnAction(e -> {
            try {
                Files.deleteIfExists(NOTES);
            } catch (Exception ignored) { }
            log.clear();
        });

        getChildren().addAll(title, sub, log, clear);
        load();
    }

    private void load() {
        try {
            if (Files.isRegularFile(NOTES)) log.setText(Files.readString(NOTES, StandardCharsets.UTF_8));
        } catch (Exception e) {
            log.setText("(unreadable: " + e.getMessage() + ")");
        }
    }
}

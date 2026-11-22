package com.ztsec.ghost;

import javafx.geometry.Insets;
import javafx.geometry.Pos;
import javafx.scene.control.Button;
import javafx.scene.control.Label;
import javafx.scene.control.TextField;
import javafx.scene.layout.HBox;
import javafx.scene.layout.VBox;
import javafx.stage.FileChooser;

import java.io.File;
import java.nio.file.Path;

/** Single-file seal and open. */
public final class VaultPanel extends VBox {
    private final TextField codeField = new TextField();
    private final Label status = new Label();

    public VaultPanel() {
        setPadding(new Insets(24));
        setSpacing(14);

        Label title = new Label("VAULT");
        title.setStyle("-fx-text-fill: " + Theme.INK
                + "; -fx-font-family: 'monospace'; -fx-font-size: 16px; -fx-font-weight: bold;");
        Label sub = new Label("One file in, one .zt01 out. The original is left in place.");
        Theme.caption(sub);

        Button make = new Button("SEAL A FILE");
        Theme.primary(make);
        make.setOnAction(e -> sealFile());

        codeField.setPromptText("recovery code");
        codeField.setStyle("-fx-background-color: " + Theme.PANEL + "; -fx-text-fill: " + Theme.INK
                + "; -fx-border-color: " + Theme.LINE + "; -fx-font-family: 'monospace'; -fx-padding: 9;");

        Button open = new Button("OPEN A .zt01");
        Theme.secondary(open);
        open.setOnAction(e -> openFile());

        HBox row = new HBox(10, codeField, open);
        row.setAlignment(Pos.CENTER_LEFT);

        status.setStyle("-fx-text-fill: " + Theme.MUTE + "; -fx-font-family: 'monospace'; -fx-font-size: 12px;");
        status.setWrapText(true);

        getChildren().addAll(title, sub, make, row, status);
    }

    private void sealFile() {
        FileChooser chooser = new FileChooser();
        File source = chooser.showOpenDialog(getScene().getWindow());
        if (source == null) return;
        try {
            Path path = source.toPath();
            Path out = path.resolveSibling(path.getFileName() + SealedFormat.EXTENSION);
            MasterKey master = MasterKey.generate();
            new FileVault().seal(path, out, master);
            status.setText("sealed " + out.getFileName() + "  |  code: " + master.recoveryCode());
        } catch (Exception e) {
            status.setText("failed: " + e.getMessage());
        }
    }

    private void openFile() {
        FileChooser chooser = new FileChooser();
        chooser.getExtensionFilters().add(new FileChooser.ExtensionFilter("Sealed", "*.zt01"));
        File sealed = chooser.showOpenDialog(getScene().getWindow());
        if (sealed == null) return;
        try {
            Path path = sealed.toPath();
            String name = new FileVault().originalName(path);
            new FileVault().open(path, path.resolveSibling(name), MasterKey.fromRecoveryCode(codeField.getText()));
            status.setText("restored " + name);
        } catch (Exception e) {
            status.setText("failed: " + e.getMessage());
        }
    }
}

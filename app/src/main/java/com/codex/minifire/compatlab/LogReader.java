package com.codex.minifire.compatlab;

import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

final class LogReader {
    private static final Pattern TIME = Pattern.compile("[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}(?:\\.[0-9]{1,3})?");
    static final class Result {
        final List<String> rows; final boolean available;
        Result(List<String> rows, boolean available) { this.rows = rows; this.available = available; }
    }
    private LogReader() {}
    static Result read() {
        List<String> rows = new ArrayList<>();
        Process process = null;
        ScheduledExecutorService timer = Executors.newSingleThreadScheduledExecutor();
        try {
            // Fixed, read-only command. No account directories or global log mutation.
            process = new ProcessBuilder("su", "-c", "tail -n 1600 /data/adb/lspd/log/modules_*.log 2>/dev/null | grep -F MinifireCompatLab | tail -n 160")
                    .redirectErrorStream(true).start();
            final Process running = process;
            timer.schedule(running::destroyForcibly, 8, TimeUnit.SECONDS);
            try (InputStreamReader input = new InputStreamReader(process.getInputStream(), StandardCharsets.UTF_8)) {
                StringBuilder line = new StringBuilder(); boolean overflow = false; int total = 0, value;
                while ((value = input.read()) != -1 && total++ < 262144) {
                    if (value == '\n') { if (!overflow) append(rows, line.toString()); line.setLength(0); overflow = false; }
                    else if (line.length() < 1024) line.append((char) value);
                    else overflow = true;
                }
                if (!overflow && line.length() > 0) append(rows, line.toString());
            }
            boolean complete = process.waitFor(1, TimeUnit.SECONDS) && process.exitValue() == 0;
            return new Result(rows, complete);
        } catch (Exception ignored) { return new Result(rows, false); }
        finally { if (process != null) process.destroyForcibly(); timer.shutdownNow(); }
    }
    private static void append(List<String> rows, String raw) {
        String safe = DiagnosticText.safeLine(raw);
        if (safe == null) return;
        Matcher time = TIME.matcher(raw.substring(0, raw.indexOf("MinifireCompatLab ")));
        String stamp = time.find() ? time.group().replace('T', ' ') + " " : "";
        rows.add(stamp + safe); if (rows.size() > 160) rows.remove(0);
    }
}

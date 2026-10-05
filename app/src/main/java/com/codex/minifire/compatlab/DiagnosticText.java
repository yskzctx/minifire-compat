package com.codex.minifire.compatlab;

public final class DiagnosticText {
    private DiagnosticText() {}
    public static String safeLine(String line) {
        if (line == null || line.length() > 1024 || line.indexOf('\n') >= 0 || line.indexOf('\r') >= 0) return null;
        int start = line.indexOf("MinifireCompatLab ");
        if (start < 0) return null;
        String text = line.substring(start);
        String[] parts = text.split(" ", -1);
        if (parts.length < 2 || parts.length > 20) return null;
        if (!"event".equals(parts[1])) {
            if (parts.length == 2) return format(parts[1], null);
            if (parts.length != 3) return null;
            Throwable category;
            switch (parts[2]) {
                case "access_denied": category = new SecurityException(); break;
                case "bad_argument": category = new IllegalArgumentException(); break;
                case "failed": category = new RuntimeException(); break;
                default: return null;
            }
            return format(parts[1], category);
        }
        if (parts.length < 3) return null;
        String[] keys = new String[parts.length - 3]; int[] values = new int[keys.length];
        for (int i = 3; i < parts.length; i++) {
            String[] field = parts[i].split("=", -1);
            if (field.length != 2 || !field[1].matches("-?[0-9]{1,11}")) return null;
            keys[i - 3] = field[0];
            try { values[i - 3] = Integer.parseInt(field[1]); } catch (NumberFormatException ignored) { return null; }
        }
        String filtered = numericEvent(parts[2], keys, values);
        // Reject the whole row if any field was removed or normalized.
        return text.equals(filtered) ? filtered : null;
    }
    public static String format(String event, Throwable error) {
        if (event == null) return null;
        switch (event) {
            case "entry": case "attach": case "settings_begin": case "settings_read":
            case "settings_null": case "settings_error": case "init_error":
            case "settings_shared": case "settings_remote": case "settings_unavailable":
            case "version_rejected": case "java_hooks_error": case "native_load_error":
                break;
            default: return null;
        }
        String suffix = error == null ? "" : error instanceof SecurityException ? " access_denied" :
                error instanceof IllegalArgumentException ? " bad_argument" : " failed";
        // Never access the exception message, stack trace, class name or callback data.
        return "MinifireCompatLab " + event + suffix;
    }
    public static String numericEvent(String event, String[] keys, int[] values) {
        if (event == null || keys == null || values == null || keys.length != values.length || keys.length > 16) return null;
        switch (event) {
            case "hook_ready": case "hook_missing": case "unsupported_version": case "sdk_channel":
            case "package_channel": case "own_sdk_channel": case "current_sdk_channel":
            case "phone_start": case "phone_code_start": case "auth_result": case "hook_error":
            case "native_state": case "native_error": case "terminal_request": case "lobby_request":
            case "terminal_response": break;
            default: return null;
        }
        StringBuilder result = new StringBuilder("MinifireCompatLab event ").append(event);
        for (int i = 0; i < keys.length; i++) {
            if (keys[i] == null) continue;
            switch (keys[i]) {
                case "original": case "selected": case "code": case "hooks": case "stage": case "decode_ready":
                case "os_original": case "os_selected": case "channel_original": case "channel_selected":
                case "version_profile":
                    result.append(' ').append(keys[i]).append('=').append(values[i]); break;
                default: break;
            }
        }
        return result.toString();
    }
}

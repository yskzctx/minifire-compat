package com.codex.minifire.compatlab;

import android.content.ContentProvider;
import android.content.ContentValues;
import android.content.SharedPreferences;
import android.database.Cursor;
import android.net.Uri;
import android.os.Binder;
import android.os.Bundle;
import android.os.Process;

public final class SettingsProvider extends ContentProvider {
    public static final Uri URI = Uri.parse("content://com.codex.minifire.compatlab.settings");
    static final String PREFS = "settings";
    static final String[] EVENTS = {"hook_ready", "hook_missing", "unsupported_version", "sdk_channel",
            "package_channel", "own_sdk_channel", "current_sdk_channel",
            "phone_start", "phone_code_start", "auth_result", "hook_error", "native_state", "native_error",
            "terminal_request", "lobby_request", "terminal_response"};
    @Override public boolean onCreate() { return true; }

    private boolean allowed() {
        int caller = Binder.getCallingUid();
        if (caller == Process.myUid()) return true;
        String[] packages = getContext().getPackageManager().getPackagesForUid(caller);
        if (packages != null) for (String pkg : packages) if (HookPolicy.GAME.equals(pkg)) return true;
        return false;
    }
    private SharedPreferences prefs() { return getContext().getSharedPreferences(PREFS, 0); }
    @Override public synchronized Bundle call(String method, String arg, Bundle extras) {
        if (!allowed()) throw new SecurityException("Caller is outside the module scope");
        Bundle result = new Bundle();
        if ("read".equals(method)) {
            result.putInt("mode", prefs().getInt("mode", 0));
            result.putInt("target", prefs().getInt("target", -1));
        } else if ("event".equals(method) && extras != null) {
            String event = extras.getString("event", "");
            boolean known = false;
            for (String candidate : EVENTS) if (candidate.equals(event)) known = true;
            if (!known) return result;
            // Accept only fixed event IDs and integer values. Raw callback bodies never reach storage.
            String entry = System.currentTimeMillis() + " " + event;
            for (String key : new String[]{"original", "selected", "code", "hooks", "stage", "decode_ready",
                    "os_original", "os_selected", "channel_original", "channel_selected", "version_profile"}) {
                if (extras.containsKey(key)) entry += " " + key + "=" + extras.getInt(key);
            }
            String history = prefs().getString("history", "");
            String[] lines = history.isEmpty() ? new String[0] : history.split("\n");
            StringBuilder bounded = new StringBuilder();
            for (int i = Math.max(0, lines.length - 79); i < lines.length; i++) bounded.append(lines[i]).append('\n');
            bounded.append(entry);
            prefs().edit().putString("history", bounded.toString()).apply();
        }
        return result;
    }
    // Configuration changes and diagnostic history are accessible only through the module's own UI.
    @Override public Cursor query(Uri uri, String[] p, String s, String[] a, String o) { return null; }
    @Override public String getType(Uri uri) { return null; }
    @Override public Uri insert(Uri uri, ContentValues v) { throw new UnsupportedOperationException(); }
    @Override public int update(Uri uri, ContentValues v, String s, String[] a) { throw new UnsupportedOperationException(); }
    @Override public int delete(Uri uri, String s, String[] a) { throw new UnsupportedOperationException(); }
}

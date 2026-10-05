package com.codex.minifire.compatlab;

import android.content.Context;
import android.content.SharedPreferences;

final class SettingsStore {
    private SettingsStore() {}
    static boolean publish(Context context, int mode, int target) {
        try {
            if (mode < 0 || mode > 5 || target < -1 || target > 1000000 || (mode == 2 && target < 0)) return false;
            if (mode == 5 && !"1.0.77".equals(context.getPackageManager().getPackageInfo(HookPolicy.GAME, 0).versionName)) return false;
            SharedPreferences remote = CompatApplication.remote(); if (remote == null) return false;
            SharedPreferences prefs = context.getSharedPreferences(SettingsProvider.PREFS, 0);
            int remembered = SettingsSelector.resumeMode(prefs.getInt("mode", 0), prefs.getInt("preferred_mode", 5), prefs.getInt("target", -1));
            // Persist only numeric settings in the framework database. No app launch
            // or exported provider is needed when the game reads them after boot.
            if (!remote.edit().clear().putInt("mode", mode).putInt("target", target).putBoolean("ready", true).commit()) return false;
            boolean saved = prefs.edit().putInt("mode", mode).putInt("target", target)
                    .putInt("preferred_mode", mode > 0 ? mode : remembered).commit();
            if (!saved) remote.edit().putBoolean("ready", false).commit();
            return saved;
        } catch (RuntimeException | android.content.pm.PackageManager.NameNotFoundException ignored) { return false; }
    }
}

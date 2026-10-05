package com.codex.minifire.compatlab;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;

// Exported only behind the platform DUMP permission, for authorized ADB
// configuration. It accepts no account fields and affects only this module.
public final class CommandConfigReceiver extends BroadcastReceiver {
    @Override public void onReceive(Context context, Intent intent) {
        if ("com.codex.minifire.compatlab.STATE".equals(intent.getAction())) {
            android.content.SharedPreferences saved = context.getSharedPreferences(SettingsProvider.PREFS, 0);
            setResultData("STATE mode=" + saved.getInt("mode", 0) + " target=" + saved.getInt("target", -1)
                    + " preferred=" + saved.getInt("preferred_mode", 0)
                    + " remoteReady=" + (CompatApplication.remote() != null && CompatApplication.remote().getBoolean("ready", false) ? 1 : 0)
                    + " frameworkApi=" + CompatApplication.frameworkApi);
            return;
        }
        if (!"com.codex.minifire.compatlab.PREPARE".equals(intent.getAction())) return;
        int mode = intent.getIntExtra("mode", -1), target = intent.getIntExtra("target", -1);
        if (mode < 0 || mode > 5 || target < -1 || target > 1000000 || (mode == 2 && target < 0)) {
            setResultData("CONFIG_INVALID"); return;
        }
        if (mode == 5) {
            try {
                if (!"1.0.77".equals(context.getPackageManager().getPackageInfo(HookPolicy.GAME, 0).versionName)) {
                    setResultData("CONFIG_VERSION_UNSUPPORTED"); return;
                }
            } catch (android.content.pm.PackageManager.NameNotFoundException ignored) {
                setResultData("CONFIG_VERSION_UNSUPPORTED"); return;
            }
        }
        setResultData(SettingsStore.publish(context, mode, target) ? "CONFIG_OK" : "CONFIG_SHARED_UNAVAILABLE");
    }
}

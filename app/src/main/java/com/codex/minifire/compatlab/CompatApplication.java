package com.codex.minifire.compatlab;

import android.app.Application;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.Looper;
import java.util.concurrent.CopyOnWriteArrayList;
import io.github.libxposed.service.XposedService;
import io.github.libxposed.service.XposedServiceHelper;

public final class CompatApplication extends Application {
    private static volatile SharedPreferences remote;
    static volatile int frameworkApi;
    private static final CopyOnWriteArrayList<Runnable> listeners = new CopyOnWriteArrayList<>();
    static SharedPreferences remote() { return remote; }
    static void listen(Runnable listener) { listeners.add(listener); }
    static void forget(Runnable listener) { listeners.remove(listener); }
    private void changed() { new Handler(Looper.getMainLooper()).post(() -> { for (Runnable listener : listeners) listener.run(); }); }
    @Override public void onCreate() {
        super.onCreate();
        XposedServiceHelper.registerListener(new XposedServiceHelper.OnServiceListener() {
            @Override public void onServiceBind(XposedService service) {
                try {
                    frameworkApi = service.getApiVersion();
                    remote = service.getRemotePreferences("login_config");
                    if (!remote.getBoolean("ready", false)) {
                        SharedPreferences local = getSharedPreferences(SettingsProvider.PREFS, 0);
                        SharedPreferences migration = getSharedPreferences("modern_migration", 0);
                        int mode = migration.contains("mode") ? migration.getInt("mode", 0) : local.getInt("mode", 0);
                        int target = migration.contains("target") ? migration.getInt("target", -1) : local.getInt("target", -1);
                        if (SettingsStore.publish(CompatApplication.this, mode, target)) migration.edit().clear().apply();
                    } else {
                        // Framework settings, including an explicit OFF, are authoritative.
                        getSharedPreferences(SettingsProvider.PREFS, 0).edit()
                                .putInt("mode", remote.getInt("mode", 0)).putInt("target", remote.getInt("target", -1)).commit();
                    }
                } catch (RuntimeException ignored) { remote = null; }
                changed();
            }
            @Override public void onServiceDied(XposedService service) { remote = null; changed(); }
        });
    }
}

package com.codex.minifire.compatlab;

import android.app.Application;
import android.content.Context;
import android.content.SharedPreferences;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Set;
import java.util.WeakHashMap;
import io.github.libxposed.api.XposedModule;
import io.github.libxposed.api.XposedInterface;

public final class HookEntry extends XposedModule {
    private String process;
    private boolean initialized;
    private final Set<Object> loginRequests = Collections.synchronizedSet(Collections.newSetFromMap(new WeakHashMap<>()));
    @Override public void onModuleLoaded(ModuleLoadedParam param) { process = param.getProcessName(); }
    @Override public void onPackageReady(PackageReadyParam param) {
        if (!param.isFirstPackage() || !HookPolicy.isTarget(param.getPackageName(), process)) return;
        diagnostic("entry", null);
        try {
            hook(Application.class.getDeclaredMethod("attach", Context.class)).intercept(chain -> {
                Object result = chain.proceed();
                if (!initialized) { initialized = true; initialize((Context) chain.getArg(0), param.getClassLoader()); }
                return result;
            });
        } catch (Throwable error) { diagnostic("init_error", error); }
    }
    private void initialize(Context context, ClassLoader loader) {
        diagnostic("attach", null);
        try {
            SharedPreferences remote = getRemotePreferences("login_config");
            SettingsSelector.Snapshot settings = SettingsSelector.read(() -> new SettingsSelector.Snapshot(
                    remote.getInt("mode", 0), remote.getInt("target", -1), remote.getBoolean("ready", false)), () -> null);
            diagnostic(settings.ready ? "settings_remote" : "settings_unavailable", null);
            int mode = settings.mode; if (mode == 0) return;
            String version = context.getPackageManager().getPackageInfo(HookPolicy.GAME, 0).versionName;
            if (!HookPolicy.supportedVersion(version) || (mode == 5 && !"1.0.77".equals(version))) { diagnostic("version_rejected", null); return; }
            // The one-switch product preserves SDK credentials and uses the verified
            // native login path; old Java SDK channel experiments are not enabled.
            if (mode < 3 || mode > 5) { event("unsupported_version", new String[0], new int[0]); return; }
            observeAuthentication(loader);
            System.loadLibrary("minifire_login"); NativeBridge.configure(mode);
            Handler handler = new Handler(Looper.getMainLooper());
            handler.post(new Runnable() {
                int[] previous;
                @Override public void run() {
                    try {
                        int[] state = NativeBridge.snapshot(); if (state == null || state.length != 16) return;
                        if (previous == null || state[0] != previous[0]) event("native_state", new String[]{"stage","decode_ready"}, new int[]{state[0],state[13]});
                        if (state[1]>0 && (previous==null || state[1]!=previous[1])) request(state,3,14,"terminal_request");
                        if (state[2]>0 && (previous==null || state[2]!=previous[2])) request(state,7,15,"lobby_request");
                        if (state[12]>0 && (previous==null || state[12]!=previous[12])) event("terminal_response",new String[]{"code"},new int[]{state[11]});
                        previous=state; handler.postDelayed(this,3000);
                    } catch (Throwable ignored) { event("native_error",new String[0],new int[0]); }
                }
            });
        } catch (Throwable error) { diagnostic("init_error", error); }
    }
    private void observeAuthentication(ClassLoader loader) {
        ArrayList<XposedInterface.HookHandle> handles = new ArrayList<>();
        try {
            Class<?> service=loader.loadClass("com.minitech.open.login.core.MNWSDKService");
            Class<?> info=loader.loadClass("com.minitech.open.login.module.CallInfo");
            Method login=service.getDeclaredMethod("mobileLogin",info);
            Method response=service.getDeclaredMethod("doWrapResponse",info,int.class,String.class,String.class);
            handles.add(hook(login).intercept(chain -> {
                Object request=chain.getArg(0); loginRequests.add(request); event("phone_start",new String[0],new int[0]);
                try { return chain.proceed(); } catch (Throwable failure) { loginRequests.remove(request); throw failure; }
            }));
            handles.add(hook(response).intercept(chain -> {
                Object result=chain.proceed();
                if (loginRequests.remove(chain.getArg(0))) event("auth_result",new String[]{"code"},new int[]{(Integer)chain.getArg(1)});
                return result;
            }));
            event("hook_ready",new String[]{"hooks"},new int[]{handles.size()});
        } catch (Throwable ignored) { for (XposedInterface.HookHandle handle:handles) handle.unhook(); event("hook_missing",new String[0],new int[0]); }
    }
    private void request(int[] state,int offset,int profile,String name) {
        event(name,new String[]{"os_original","os_selected","channel_original","channel_selected","version_profile"},
                new int[]{state[offset],state[offset+1],state[offset+2],state[offset+3],state[profile]});
    }
    private void event(String name,String[] keys,int[] values) {
        try { String safe=DiagnosticText.numericEvent(name,keys,values); if (safe!=null) log(Log.INFO,"MinifireCompatLab",safe); } catch (Throwable ignored) { }
    }
    private void diagnostic(String name,Throwable error) {
        try { String safe=DiagnosticText.format(name,error); if (safe!=null) log(Log.INFO,"MinifireCompatLab",safe); } catch (Throwable ignored) { }
    }
}

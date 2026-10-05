package com.codex.minifire.compatlab;

public final class HookPolicy {
    public static final String GAME = "com.miniworldroyale.sparkgame";
    public static final String VERSION = "1.0.77";
    public static boolean supportedVersion(String version) {
        return "1.0.76".equals(version) || VERSION.equals(version);
    }
    private HookPolicy() {}
    public static boolean isTarget(String packageName, String processName) {
        return GAME.equals(packageName) && GAME.equals(processName);
    }
    public static int channel(String packageName, String processName, String version,
                              int mode, int target, String operation, int original) {
        if (!isTarget(packageName, processName) || !supportedVersion(version)
                || mode != 2 || target < 0 || target > 1000000) return original;
        if ("phone-login".equals(operation) || "phone-code".equals(operation)
                || "channel-query".equals(operation)) return target;
        return original;
    }
}

package com.codex.minifire.compatlab;

public final class SettingsSelector {
    private SettingsSelector() {}
    public interface Source { Snapshot read(); }
    public static final class Snapshot {
        public final int mode, target;
        public final boolean ready;
        public Snapshot(int mode, int target, boolean ready) {
            this.mode = mode; this.target = target; this.ready = ready;
        }
    }
    private static Snapshot disabled() { return new Snapshot(0, -1, false); }
    private static boolean validProfile(int mode, int target) {
        return mode >= 1 && mode <= 5 && (mode != 2 || (target >= 0 && target <= 1000000));
    }
    public static int resumeMode(int current, int remembered, int target) {
        if (validProfile(current, target)) return current;
        if (validProfile(remembered, target)) return remembered;
        return 5;
    }
    public static Snapshot toggle(boolean enabled, int current, int remembered, int target) {
        return new Snapshot(enabled ? resumeMode(current, remembered, target) : 0,
                target >= -1 && target <= 1000000 ? target : -1, true);
    }
    public static Snapshot read(Source primary, Source fallback) {
        Snapshot selected = null;
        try { selected = primary.read(); } catch (RuntimeException ignored) { }
        // An explicit primary "off" is authoritative; never revive stale shared settings.
        if (selected == null) {
            try { selected = fallback.read(); } catch (RuntimeException ignored) { }
        }
        if (selected == null || !selected.ready || selected.mode < 0 || selected.mode > 5 ||
                (selected.mode == 2 && (selected.target < 0 || selected.target > 1000000))) return disabled();
        return selected;
    }
}

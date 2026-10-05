import com.codex.minifire.compatlab.SettingsSelector;

public final class SettingsSelectorTest {
    private static void check(int expected, SettingsSelector.Source primary, SettingsSelector.Source fallback) {
        if (SettingsSelector.read(primary, fallback).mode != expected)
            throw new AssertionError("Settings recovery/disable contract failed");
    }
    public static void main(String[] args) {
        SettingsSelector.Source enabled = () -> new SettingsSelector.Snapshot(4, -1, true);
        check(4, () -> { throw new IllegalArgumentException("LOCAL-SECRET"); }, enabled);
        check(5, () -> null, () -> new SettingsSelector.Snapshot(5,-1,true));
        check(0, () -> new SettingsSelector.Snapshot(0, -1, true), enabled);
        check(0, () -> null, () -> new SettingsSelector.Snapshot(4, -1, false));
        check(0, () -> null, () -> new SettingsSelector.Snapshot(999, -1, true));
        check(0, () -> null, () -> new SettingsSelector.Snapshot(2, -1, true));
        check(0, () -> null, () -> { throw new SecurityException("LOCAL-SECRET"); });
        check(3, () -> new SettingsSelector.Snapshot(3, -1, true), () -> { throw new AssertionError("Unneeded fallback"); });
        System.out.println("PASS: 8 settings recovery cases");
    }
}

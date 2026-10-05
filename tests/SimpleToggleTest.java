import com.codex.minifire.compatlab.SettingsSelector;
import java.lang.reflect.Method;

public final class SimpleToggleTest {
    // Catches replacing the working profile on enable, forgetting it on disable,
    // and reviving an invalid SDK profile after a process restart.
    private static int selected(boolean enabled, int current, int remembered, int target) throws Exception {
        try {
            Method method = SettingsSelector.class.getMethod("toggle", boolean.class, int.class, int.class, int.class);
            return ((SettingsSelector.Snapshot) method.invoke(null, enabled, current, remembered, target)).mode;
        } catch (NoSuchMethodException missing) {
            throw new AssertionError("One-switch profile preservation is not implemented");
        }
    }
    private static void check(int expected, boolean enabled, int current, int remembered, int target) throws Exception {
        if (selected(enabled, current, remembered, target) != expected) throw new AssertionError("Working profile changed");
    }
    public static void main(String[] args) throws Exception {
        check(4, true, 4, 0, -1);
        check(5, true, 5, 4, -1);
        check(0, false, 5, 4, -1);
        check(5, true, 0, 5, -1);
        check(3, true, 0, 3, -1);
        check(2, true, 0, 2, 23);
        check(5, true, 0, 2, -1);
        check(5, true, 999, 999, -1);
        check(5, true, 0, 0, -1);
        System.out.println("PASS: 9 persistent toggle cases");
    }
}

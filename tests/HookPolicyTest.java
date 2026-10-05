import com.codex.minifire.compatlab.HookPolicy;

public final class HookPolicyTest {
    private static final String GAME = "com.miniworldroyale.sparkgame";
    private static int count;
    private static void check(String name, int expected, String pkg, String process,
                              String version, int mode, int target, String op, int original) {
        int actual = HookPolicy.channel(pkg, process, version, mode, target, op, original);
        if (actual != expected) throw new AssertionError(name + ": expected " + expected + ", got " + actual);
        count++;
    }
    public static void main(String[] args) {
        // A wrong process gate would make these calls alter channels in unrelated apps.
        check("unrelated app keeps original", 7, "com.example.bank", "com.example.bank", "1.0.77", 2, 123, "phone-login", 7);
        check("forged process name does not broaden package scope", 7, "com.example.bank", GAME, "1.0.77", 2, 123, "phone-login", 7);
        check("game auxiliary process keeps original", 7, GAME, GAME + ":push", "1.0.77", 2, 123, "phone-login", 7);
        check("system process keeps original", 7, "android", "system_server", "1.0.77", 2, 123, "phone-login", 7);
        check("null identity keeps original", 7, null, null, "1.0.77", 2, 123, "phone-login", 7);
        // Removing the mode/version/parameter checks would enable unintended experiments.
        check("disabled keeps original", 7, GAME, GAME, "1.0.77", 0, 123, "phone-login", 7);
        check("observation keeps original", 7, GAME, GAME, "1.0.77", 1, 123, "phone-login", 7);
        check("native OS mode preserves Java SDK channel", 7, GAME, GAME, "1.0.77", 3, 123, "phone-login", 7);
        check("native game channel mode preserves Java SDK channel", 7, GAME, GAME, "1.0.77", 4, 123, "phone-login", 7);
        check("native version profile preserves Java SDK channel", 7, GAME, GAME, "1.0.77", 5, 123, "phone-login", 7);
        check("unanalysed version keeps original", 7, GAME, GAME, "1.0.78", 2, 123, "phone-login", 7);
        check("missing target keeps original", 7, GAME, GAME, "1.0.77", 2, -1, "phone-login", 7);
        check("out-of-range target keeps original", 7, GAME, GAME, "1.0.77", 2, Integer.MAX_VALUE, "phone-login", 7);
        check("payment keeps original", 7, GAME, GAME, "1.0.77", 2, 123, "payment", 7);
        check("account binding keeps original", 7, GAME, GAME, "1.0.77", 2, 123, "bind-phone", 7);
        check("unrelated SDK call keeps original", 7, GAME, GAME, "1.0.77", 2, 123, null, 7);
        // Fixtures use a synthetic channel, not an assumed iOS channel.
        check("opted-in phone login uses specified channel", 123, GAME, GAME, "1.0.77", 2, 123, "phone-login", 7);
        check("opted-in login verification uses specified channel", 123, GAME, GAME, "1.0.77", 2, 123, "phone-code", 7);
        check("opted-in channel query uses specified channel", 123, GAME, GAME, "1.0.77", 2, 123, "channel-query", 7);
        check("verified installed 1.0.76 supports phone login", 123, GAME, GAME, "1.0.76", 2, 123, "phone-login", 7);
        System.out.println("PASS: " + count + " policy cases");
    }
}

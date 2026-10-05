import com.codex.minifire.compatlab.DiagnosticText;

public final class DiagnosticTextTest {
    private static void check(boolean condition) {
        if (!condition) throw new AssertionError("Diagnostic privacy contract failed");
    }
    public static void main(String[] args) {
        check(DiagnosticText.format("token=LOCAL-SECRET", null) == null);
        check(DiagnosticText.format(null, null) == null);
        check("MinifireCompatLab settings_error access_denied".equals(
            DiagnosticText.format("settings_error", new SecurityException("LOCAL-SECRET"))));
        RuntimeException trap = new RuntimeException("LOCAL-SECRET") {
            @Override public String getMessage() { throw new AssertionError("Raw message accessed"); }
            @Override public String toString() { throw new AssertionError("Raw exception accessed"); }
        };
        check("MinifireCompatLab init_error failed".equals(DiagnosticText.format("init_error", trap)));
        check("MinifireCompatLab entry".equals(DiagnosticText.format("entry", null)));
        check(DiagnosticText.numericEvent("LOCAL-SECRET", new String[0], new int[0]) == null);
        check("MinifireCompatLab event native_state stage=4".equals(DiagnosticText.numericEvent(
            "native_state", new String[]{"LOCAL-SECRET", "stage"}, new int[]{999, 4})));
        check(DiagnosticText.numericEvent("native_state", new String[]{"stage"}, new int[0]) == null);
        System.out.println("PASS: 8 diagnostic privacy cases");
    }
}

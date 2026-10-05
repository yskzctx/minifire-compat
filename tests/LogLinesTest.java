import com.codex.minifire.compatlab.DiagnosticText;
import java.lang.reflect.Method;

public final class LogLinesTest {
    // Catches copying unrelated framework logs, credentials, arbitrary suffixes,
    // or unbounded fields into the application's private journal.
    private static String parse(String line) throws Exception {
        try { return (String) DiagnosticText.class.getMethod("safeLine", String.class).invoke(null, line); }
        catch (NoSuchMethodException missing) { throw new AssertionError("Safe log import is not implemented"); }
    }
    private static void same(String expected, String line) throws Exception {
        String actual = parse(line);
        if (expected == null ? actual != null : !expected.equals(actual)) throw new AssertionError("Log privacy boundary failed");
    }
    public static void main(String[] args) throws Exception {
        same("MinifireCompatLab event terminal_response code=200", "[ 2026-10-05T12:00:00.123 1234 ] MinifireCompatLab event terminal_response code=200");
        same("MinifireCompatLab settings_error bad_argument", "MinifireCompatLab settings_error bad_argument");
        same("MinifireCompatLab event native_state stage=4 decode_ready=1", "MinifireCompatLab event native_state stage=4 decode_ready=1");
        same(null, "OtherModule token=LOCAL-SECRET");
        same(null, "MinifireCompatLab event auth_result code=0 token=LOCAL-SECRET");
        same(null, "MinifireCompatLab event auth_result code=0\nLOCAL-SECRET");
        same(null, "MinifireCompatLab event terminal_response code=999999999999999999999");
        same(null, "MinifireCompatLab unknown LOCAL-SECRET");
        same(null, "MinifireCompatLab init_error failed LOCAL-SECRET");
        same(null, null);
        System.out.println("PASS: 10 log import privacy cases");
    }
}

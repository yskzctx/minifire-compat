package com.codex.minifire.compatlab;

import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.SharedPreferences;
import android.graphics.Typeface;
import android.os.Bundle;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;
import java.text.SimpleDateFormat;
import java.util.Arrays;
import java.util.Date;
import java.util.HashSet;
import java.util.Locale;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class LogsActivity extends Activity {
    private SharedPreferences prefs;
    private TextView history, status;
    private Button refresh;
    private final ExecutorService worker = Executors.newSingleThreadExecutor();
    private int generation;
    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }
    private TextView text(LinearLayout root, String value, int size) {
        TextView view = new TextView(this); view.setText(value); view.setTextSize(size);
        view.setTextColor(UiKit.INK); view.setPadding(0, dp(8), 0, dp(8)); root.addView(view); return view;
    }
    private Button button(LinearLayout root, String value, Runnable action) {
        Button view = UiKit.button(this,value,false); view.setOnClickListener(v -> action.run());
        LinearLayout.LayoutParams params=new LinearLayout.LayoutParams(-1,dp(48)); params.bottomMargin=dp(10); root.addView(view,params); return view;
    }
    @Override public void onCreate(Bundle state) {
        super.onCreate(state); UiKit.window(this); prefs = getSharedPreferences(SettingsProvider.PREFS, 0);
        ScrollView scroll = new ScrollView(this); LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL); root.setPadding(dp(24), dp(24), dp(24), dp(28)); scroll.setBackgroundColor(UiKit.BACKGROUND);
        scroll.addView(root); setContentView(scroll);
        text(root, "运行日志", 28).setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));
        text(root, "模块状态与登录结果 · 仅保留必要诊断", 13).setTextColor(UiKit.MUTED);
        status = text(root, "", 14);
        refresh = button(root, "刷新日志", this::load);
        button(root, "复制日志", () -> {
            ((ClipboardManager) getSystemService(CLIPBOARD_SERVICE)).setPrimaryClip(ClipData.newPlainText("迷枪兼容日志", history.getText()));
            Toast.makeText(this, "日志已复制", Toast.LENGTH_SHORT).show();
        });
        button(root, "清空日志", () -> {
            generation++;
            prefs.edit().putString("ignored_framework", prefs.getString("framework_journal", ""))
                    .remove("framework_journal").remove("history").apply();
            refresh.setEnabled(true); status.setText("本应用日志已清空"); show();
        });
        button(root, "返回", this::finish);
        history = text(root, "", 12); history.setTextIsSelectable(true); history.setTypeface(Typeface.MONOSPACE);
        history.setPadding(dp(18),dp(18),dp(18),dp(18)); history.setBackground(UiKit.rounded(this,0xffffffff,18));
        text(root, "日志不含手机号、密码、验证码或令牌。\n框架日志读取需要 Root 权限，不影响账号兼容；清空仅清除此处显示。", 12).setTextColor(UiKit.MUTED);
        show(); load();
    }
    private void load() {
        final int request = ++generation;
        refresh.setEnabled(false); status.setText("正在读取模块日志…");
        worker.execute(() -> {
            LogReader.Result result = LogReader.read();
            runOnUiThread(() -> {
                if (isFinishing() || isDestroyed() || request != generation) return;
                refresh.setEnabled(true);
                if (result.available) prefs.edit().putString("framework_journal", String.join("\n", result.rows)).apply();
                status.setText(result.available ? "已刷新 · 最近 160 条框架记录" : "框架日志暂不可读，显示已有本地记录；需要时请授予本应用 Root 权限");
                show();
            });
        });
    }
    private void show() {
        StringBuilder shown = new StringBuilder();
        Set<String> ignored = new HashSet<>(Arrays.asList(prefs.getString("ignored_framework", "").split("\n")));
        for (String row : prefs.getString("framework_journal", "").split("\n")) {
            if (!ignored.contains(row) && DiagnosticText.safeLine(row) != null) shown.append(row).append('\n');
        }
        SimpleDateFormat time = new SimpleDateFormat("MM-dd HH:mm:ss", Locale.ROOT);
        for (String row : prefs.getString("history", "").split("\n")) {
            int space = row.indexOf(' '); if (space < 0) continue;
            String safe = DiagnosticText.safeLine("MinifireCompatLab event " + row.substring(space + 1));
            if (safe == null) continue;
            try { shown.append(time.format(new Date(Long.parseLong(row.substring(0, space))))).append(' ').append(safe).append('\n'); }
            catch (NumberFormatException ignoredTime) { }
        }
        history.setText(shown.length() == 0 ? "暂无日志。下次启动游戏后可在这里刷新查看。" : shown.toString());
    }
    @Override protected void onDestroy() { generation++; worker.shutdownNow(); super.onDestroy(); }
}

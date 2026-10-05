package com.codex.minifire.compatlab;

import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.res.ColorStateList;
import android.os.Bundle;
import android.view.Gravity;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

public final class MainActivity extends Activity {
    private SharedPreferences prefs;
    private Switch enabled;
    private TextView status, badge;
    private boolean syncing;
    private final Runnable frameworkChanged=this::sync;
    @Override public void onCreate(Bundle state) {
        super.onCreate(state); UiKit.window(this);
        prefs=getSharedPreferences(SettingsProvider.PREFS,0);
        ScrollView scroll=new ScrollView(this); scroll.setFillViewport(true); scroll.setBackgroundColor(UiKit.BACKGROUND);
        LinearLayout root=new LinearLayout(this); root.setOrientation(LinearLayout.VERTICAL);
        root.setPadding(UiKit.dp(this,24),UiKit.dp(this,26),UiKit.dp(this,24),UiKit.dp(this,28)); scroll.addView(root); setContentView(scroll);
        LinearLayout header=new LinearLayout(this); header.setGravity(Gravity.CENTER_VERTICAL);
        TextView mark=UiKit.text(this,"M",25,0xffffffff,true); mark.setGravity(Gravity.CENTER); mark.setBackground(UiKit.rounded(this,UiKit.BLUE,16));
        header.addView(mark,new LinearLayout.LayoutParams(UiKit.dp(this,52),UiKit.dp(this,52)));
        LinearLayout names=new LinearLayout(this); names.setOrientation(LinearLayout.VERTICAL); names.setPadding(UiKit.dp(this,14),0,0,0);
        names.addView(UiKit.text(this,"迷枪兼容",23,UiKit.INK,true)); names.addView(UiKit.text(this,"苹果区账号 · 0.4.1",12,UiKit.MUTED,false)); header.addView(names); root.addView(header);
        UiKit.gap(root,30);
        root.addView(UiKit.text(this,"开启一次，\n以后直接进游戏。",30,UiKit.INK,true));
        UiKit.gap(root,10); root.addView(UiKit.text(this,"重启自动生效，无需重复打开应用",14,UiKit.MUTED,false));
        LinearLayout control=UiKit.panel(this); root.addView(control);
        LinearLayout top=new LinearLayout(this); top.setGravity(Gravity.CENTER_VERTICAL);
        TextView label=UiKit.text(this,"账号兼容",16,UiKit.INK,true); top.addView(label,new LinearLayout.LayoutParams(0,-2,1));
        badge=UiKit.text(this,"",11,UiKit.GREEN,true); badge.setPadding(UiKit.dp(this,10),UiKit.dp(this,5),UiKit.dp(this,10),UiKit.dp(this,5)); top.addView(badge); control.addView(top);
        UiKit.gap(control,18);
        enabled=new Switch(this); enabled.setId(R.id.compat_switch); enabled.setText("苹果区账号"); enabled.setContentDescription("苹果区账号兼容开关");
        enabled.setTextSize(20); enabled.setTextColor(UiKit.INK); enabled.setSwitchPadding(UiKit.dp(this,20));
        enabled.setThumbTintList(new ColorStateList(new int[][]{new int[]{android.R.attr.state_checked},new int[0]},new int[]{UiKit.BLUE,0xffaab6c9}));
        enabled.setTrackTintList(new ColorStateList(new int[][]{new int[]{android.R.attr.state_checked},new int[0]},new int[]{0xffbdceff,0xffdce3ee})); control.addView(enabled,new LinearLayout.LayoutParams(-1,UiKit.dp(this,50)));
        UiKit.gap(control,10); status=UiKit.text(this,"",13,UiKit.GREEN,false); control.addView(status);
        LinearLayout logs=UiKit.panel(this); root.addView(logs);
        logs.addView(UiKit.text(this,"运行日志",17,UiKit.INK,true)); UiKit.gap(logs,6);
        logs.addView(UiKit.text(this,"查看模块加载状态与登录结果",13,UiKit.MUTED,false)); UiKit.gap(logs,16);
        Button open=UiKit.button(this,"查看日志  ›",false); open.setId(R.id.open_logs);
        open.setOnClickListener(view->startActivity(new Intent(this,LogsActivity.class))); logs.addView(open,new LinearLayout.LayoutParams(-1,UiKit.dp(this,48)));
        UiKit.gap(root,24); root.addView(UiKit.text(this,"开关更改后，退出游戏再进入即可。\n设置自动保存，应用无需后台常驻。",12,UiKit.MUTED,false));
        sync();
        enabled.setOnCheckedChangeListener((button,checked)->{
            if(syncing)return;
            int current=prefs.getInt("mode",0),target=prefs.getInt("target",-1);
            SettingsSelector.Snapshot selected=SettingsSelector.toggle(checked,current,prefs.getInt("preferred_mode",5),target);
            boolean saved=SettingsStore.publish(this,selected.mode,selected.target); sync();
            Toast.makeText(this,saved?"已保存，请退出游戏后重新进入":"保存失败，请检查 LSPosed 模块状态与游戏版本",Toast.LENGTH_LONG).show();
        });
    }
    private void sync(){
        if(enabled==null)return; syncing=true;
        int mode=prefs.getInt("mode",0); boolean on=mode>=1&&mode<=5,ready=CompatApplication.remote()!=null;
        enabled.setChecked(on); enabled.setEnabled(ready);
        badge.setText(!ready?"连接中":on?"已开启":"已关闭"); badge.setTextColor(on&&ready?UiKit.GREEN:UiKit.MUTED);
        badge.setBackground(UiKit.rounded(this,on&&ready?0xffe8f6ef:0xffeef1f6,20));
        status.setText(!ready?"正在连接 LSPosed，请确认模块已启用":on?"●  启动游戏即生效，重启后继续保持":"游戏将使用原始登录方式");
        status.setTextColor(on&&ready?UiKit.GREEN:UiKit.MUTED); syncing=false;
    }
    @Override protected void onResume(){super.onResume();sync();}
    @Override protected void onStart(){super.onStart();CompatApplication.listen(frameworkChanged);}
    @Override protected void onStop(){CompatApplication.forget(frameworkChanged);super.onStop();}
}

package com.codex.minifire.compatlab;

import android.app.Activity;
import android.content.Context;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;

final class UiKit {
    static final int INK=0xff17253e, MUTED=0xff7c899e, BLUE=0xff3866ee, BACKGROUND=0xfff3f6fc, GREEN=0xff148764;
    private UiKit() {}
    static int dp(Context context,int value) { return Math.round(value*context.getResources().getDisplayMetrics().density); }
    static GradientDrawable rounded(Context context,int color,int radius) {
        GradientDrawable drawable=new GradientDrawable(); drawable.setColor(color); drawable.setCornerRadius(dp(context,radius)); return drawable;
    }
    static void window(Activity activity) {
        activity.getWindow().setStatusBarColor(BACKGROUND); activity.getWindow().setNavigationBarColor(BACKGROUND);
        activity.getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR|View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR);
    }
    static TextView text(Context context,String value,int size,int color,boolean bold) {
        TextView view=new TextView(context); view.setText(value); view.setTextSize(size); view.setTextColor(color);
        view.setTypeface(Typeface.create(bold?"sans-serif-medium":"sans-serif",Typeface.NORMAL));
        view.setLineSpacing(dp(context,3),1); return view;
    }
    static LinearLayout panel(Context context) {
        LinearLayout panel=new LinearLayout(context); panel.setOrientation(LinearLayout.VERTICAL);
        panel.setPadding(dp(context,22),dp(context,22),dp(context,22),dp(context,22));
        GradientDrawable bg=rounded(context,0xffffffff,24); bg.setStroke(dp(context,1),0xffe7edf6); panel.setBackground(bg);
        LinearLayout.LayoutParams params=new LinearLayout.LayoutParams(-1,-2); params.topMargin=dp(context,18); panel.setLayoutParams(params); return panel;
    }
    static void gap(LinearLayout root,int height) { View gap=new View(root.getContext()); root.addView(gap,new LinearLayout.LayoutParams(1,dp(root.getContext(),height))); }
    static Button button(Context context,String label,boolean primary) {
        Button button=new Button(context); button.setText(label); button.setTextSize(14); button.setAllCaps(false);
        button.setTypeface(Typeface.create("sans-serif-medium",Typeface.NORMAL));
        button.setTextColor(primary?0xffffffff:BLUE); button.setBackground(rounded(context,primary?BLUE:0xffedf2ff,14));
        button.setMinHeight(dp(context,48)); button.setMinimumHeight(dp(context,48));
        button.setStateListAnimator(null); return button;
    }
}

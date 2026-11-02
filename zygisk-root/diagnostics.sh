#!/system/bin/sh
# Export a single phone-side snapshot. No account fields are read directly.
MODDIR=${0%/*}
OUT_DIR=${MINIFIRE_DIAG_DIR:-/sdcard/Download}
STAMP=$(date +%Y%m%d-%H%M%S)
OUT="$OUT_DIR/MinifireCompat-$STAMP-$$.txt"
mkdir -p "$OUT_DIR" || exit 1
{
    printf 'Minifire compatibility diagnostics\n'
    printf 'time='; date '+%Y-%m-%d %H:%M:%S %z'
    printf 'root_uid='; id -u
    printf 'android='; getprop ro.build.version.release
    printf 'module_dir=%s\n' "$MODDIR"
    printf '\n[module.prop]\n'
    cat "$MODDIR/module.prop"
    printf '\n[flags]\n'
    for key in game_enabled hunter_enabled; do
        printf '%s=' "$key"
        if [ -f "$MODDIR/$key" ]; then cat "$MODDIR/$key"; else printf 'missing\n'; fi
    done
    printf '\n[game package]\n'
    dumpsys package com.miniworldroyale.sparkgame | grep -m 1 'versionName=' || printf 'versionName unavailable\n'
    printf '\n[module logcat]\n'
    logcat -d -b main -b system -b crash -v threadtime -s MinifireCompatZ:V '*:S'
    printf '\n[system logcat, latest 1500 lines]\n'
    logcat -d -b main -b system -b crash -v threadtime | tail -n 1500
} > "$OUT" 2>&1
if [ -s "$OUT" ]; then
    chmod 0644 "$OUT"
    printf '%s\n' "$OUT"
else
    printf 'diagnostic file was not written\n' >&2
    exit 1
fi

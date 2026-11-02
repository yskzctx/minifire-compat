#!/system/bin/sh
MODDIR=${0%/*}
STATE="$MODDIR/state"
case "$1" in
    status)
        printf 'game='; cat "$MODDIR/game_enabled"
        printf 'stage='; if [ -f "$STATE/status" ]; then cat "$STATE/status"; else printf 'reboot_required\n'; fi
        ;;
    game)
        case "$2" in 0|1) ;; *) exit 2;; esac
        printf '%s\n' "$2" > "$MODDIR/game_enabled.tmp" && chmod 0644 "$MODDIR/game_enabled.tmp" && mv -f "$MODDIR/game_enabled.tmp" "$MODDIR/game_enabled" || exit 1
        if [ "$2" = 1 ]; then
            mkdir -p "$STATE" && chmod 0700 "$STATE" || exit 1
            sh "$MODDIR/controller.sh" </dev/null > "$STATE/controller-error.txt" 2>&1 &
        else
            sh "$MODDIR/controller.sh" stop || exit 1
        fi
        cat "$MODDIR/game_enabled"
        ;;
    logs)
        printf '[module status]\n'; sh "$MODDIR/control.sh" status
        for file in controller-error.txt cleanup.txt package-path.txt package-uid.txt prepare-progress prepare.txt trust-prepare.txt trust-mount.txt trust-error.txt route-error.txt daemon.txt; do
            if [ -s "$STATE/$file" ]; then printf '\n[%s]\n' "$file"; tail -n 20 "$STATE/$file"; fi
        done
        for file in controller.jsonl events.jsonl; do
            if [ -s "$STATE/$file" ]; then printf '\n[%s]\n' "$file"; tail -n 100 "$STATE/$file"; fi
        done
        ;;
    export)
        OUT="/sdcard/Download/MinifireExternal-$(date +%Y%m%d-%H%M%S)-$$.txt"
        mkdir -p /sdcard/Download || exit 1
        {
            printf 'Minifire external diagnostics\n'; date '+%Y-%m-%d %H:%M:%S %z'
            printf '\n[module]\n'; cat "$MODDIR/module.prop"
            printf '\n[status]\n'; sh "$MODDIR/control.sh" status
            printf '\n[game package]\n'; dumpsys package com.miniworldroyale.sparkgame | sed -n '/versionName=/p'
            for file in controller-error.txt cleanup.txt package-path.txt package-uid.txt prepare-progress prepare.txt trust-prepare.txt trust-mount.txt trust-error.txt route-error.txt daemon.txt controller.jsonl.1 controller.jsonl events.jsonl.1 events.jsonl; do
                if [ -f "$STATE/$file" ]; then printf '\n[%s]\n' "$file"; cat "$STATE/$file"; fi
            done
        } > "$OUT" 2>&1
        [ -s "$OUT" ] || exit 1
        chmod 0644 "$OUT"
        printf '%s\n' "$OUT"
        ;;
    *) exit 2;;
esac

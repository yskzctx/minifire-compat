#!/system/bin/sh
MODDIR=${0%/*}
STATE="$MODDIR/state"
. "$MODDIR/config.sh" || exit 1
read_target || { printf 'target_config_invalid\n'; exit 1; }
registered(){
    awk -v wanted="$1" '$1==wanted && $2 ~ /^[0-9]+$/ && $2>=10000 {found=1} END{exit !found}' /data/system/packages.list
}
save_flag(){
    # The module maps this inode read-only. Never rename/truncate it while games run.
    printf '%s' "$1" | dd of="$MODDIR/game_enabled" bs=1 count=1 conv=notrunc 2>/dev/null || return 1
    [ "$(head -c 1 "$MODDIR/game_enabled")" = "$1" ]
}
case "$1" in
 apps)
    awk 'BEGIN {printf "[";separator=""} $1 ~ /^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)+$/ && $2 ~ /^[0-9]+$/ && $2>=10000 {printf "%s{\"package\":\"%s\",\"uid\":%s}",separator,$1,$2;separator=","} END{print "]"}' /data/system/packages.list
    ;;
 target)
    valid_package "$2" && registered "$2" || { printf 'target_not_installed\n'; exit 1; }
    save_flag 0 || exit 1
    printf '%s\n' "$2" > "$MODDIR/target_package.tmp" && chmod 0644 "$MODDIR/target_package.tmp" && mv -f "$MODDIR/target_package.tmp" "$MODDIR/target_package" || exit 1
    printf '%s\n' "$2"
    ;;
 game)
    case "$2" in 0|1) ;; *) exit 2;; esac
    if [ "$2" = 1 ]; then registered "$GAME" || { printf 'target_not_installed\n';exit 1; }; fi
    save_flag "$2" || exit 1
    printf '%s\n' "$2"
    ;;
 status)
    printf 'target=%s\ngame=%s\n' "$GAME" "$(head -c 1 "$MODDIR/game_enabled")"
    stage=waiting_game
    if [ "$(head -c 1 "$MODDIR/game_enabled")" != 1 ]; then stage=disabled
    else
        pid=$(pidof "$GAME" 2>/dev/null | awk '{print $1}')
        case "$pid" in ''|*[!0-9]*) ;; *)
            line=$(grep -F "\"pid\":$pid," "$STATE/hooks.jsonl" 2>/dev/null | tail -n 1)
            collected=$(grep -F "\"pid\":$pid," "$STATE/system-module.log" 2>/dev/null | tail -n 1)
            [ -z "$collected" ] || line=$collected
            case "$line" in
                *'"stage":"terminal_login_rewritten"'*|*'"stage":"lobby_login_rewritten"'*) stage=login_rewritten;;
                *'"stage":"hook_installed"'*|*'"stage":"encoder_called"'*) stage=hook_installed;;
                *'"stage":"login_profile_rejected"'*) stage=login_profile_rejected;;
                *'rejected"'*|*'failed"'*|*'unavailable"'*|*'timeout"'*) stage=hook_failed;;
                *'"stage":"waiting_game_library"'*|*'"stage":"target_selected"'*) stage=waiting_library;;
            esac;;
        esac
    fi
    printf 'stage=%s\nmethod=single_pb_encode_hook\n' "$stage"
    ;;
 logs)
    printf '[module]\n'; cat "$MODDIR/module.prop"
    printf '\n[module status]\n'; sh "$MODDIR/control.sh" status
    for file in migration.txt boot.txt collector-error.txt hooks.jsonl system-module.log.2 system-module.log.1 system-module.log; do
        if [ -f "$STATE/$file" ]; then printf '\n[%s]\n' "$file"; tail -n 1500 "$STATE/$file"; fi
    done
    if [ -f "$STATE/hooks.jsonl" ] && [ "$(wc -c < "$STATE/hooks.jsonl")" -ge 1048576 ]; then
        printf '\n[file log limit]\nPrivate append log reached 1 MiB; use the rotating system-module log below.\n'
    fi
    printf '\n[system module log]\n'
    logcat -d -v threadtime -t 1500 -s MinifireCompatM:I '*:S' 2>&1
    ;;
 export)
    OUT="/sdcard/Download/MinifireMinimal-$(date +%Y%m%d-%H%M%S)-$$.txt"
    mkdir -p /sdcard/Download || exit 1
    sh "$MODDIR/control.sh" logs > "$OUT" 2>&1
    [ -s "$OUT" ] || exit 1
    chmod 0644 "$OUT" && printf '%s\n' "$OUT"
    ;;
 *) exit 2;;
esac

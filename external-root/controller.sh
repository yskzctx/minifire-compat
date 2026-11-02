#!/system/bin/sh
MODDIR=${0%/*}
STATE="$MODDIR/state"
BIN="$MODDIR/bin/minifire-external"
GAME=com.miniworldroyale.sparkgame
mkdir -p "$STATE" && chmod 0700 "$STATE" || exit 1
status(){
    stage=$1
    if [ -f "$STATE/controller.jsonl" ] && [ "$(wc -c < "$STATE/controller.jsonl")" -gt 262144 ]; then mv -f "$STATE/controller.jsonl" "$STATE/controller.jsonl.1"; fi
    printf '%s\n' "$stage" > "$STATE/status"
    printf '{"time":"%s","stage":"%s"}\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$stage" >> "$STATE/controller.jsonl"
}
ours(){
    case "$1" in ''|*[!0-9]*) return 1;; esac
    [ -r "/proc/$1/cmdline" ] || return 1
    command_line=$(tr '\000' ' ' < "/proc/$1/cmdline")
    case "$command_line" in *"$BIN"*) return 0;; esac
    return 1
}
stop_proxy(){
    if [ -f "$STATE/proxy.pid" ]; then
        IFS= read -r proxy_pid < "$STATE/proxy.pid"
        if ours "$proxy_pid"; then
            kill "$proxy_pid" 2>/dev/null || :
            count=0
            while [ "$count" -lt 20 ] && ours "$proxy_pid"; do sleep 0.2; count=$((count+1)); done
            if ours "$proxy_pid"; then kill -9 "$proxy_pid" 2>/dev/null || :; fi
        fi
    fi
    sh "$MODDIR/route.sh" stop >/dev/null 2>&1
    sh "$MODDIR/trust.sh" unmount >/dev/null 2>&1
    rm -f "$STATE/proxy.pid" "$STATE/ready" "$STATE/fatal"
    active_pid=''
}
if [ "$1" = stop ]; then stop_proxy; exit 0; fi
if ! mkdir "$STATE/controller.lock" 2>/dev/null; then
    [ -f "$STATE/controller.lock/pid" ] && IFS= read -r old < "$STATE/controller.lock/pid"
    if [ -n "$old" ] && [ -r "/proc/$old/cmdline" ]; then
        command_line=$(tr '\000' ' ' < "/proc/$old/cmdline")
        case "$command_line" in *"$MODDIR/controller.sh"*) exit 0;; esac
    fi
    rm -f "$STATE/controller.lock/pid"
    rmdir "$STATE/controller.lock" 2>/dev/null || exit 1
    mkdir "$STATE/controller.lock" || exit 1
fi
printf '%s\n' "$$" > "$STATE/controller.lock/pid"
cleanup(){ stop_proxy; rm -f "$STATE/controller.lock/pid"; rmdir "$STATE/controller.lock" 2>/dev/null || :; }
trap 'cleanup' EXIT
trap 'exit 0' INT TERM HUP
prepared=0
active_pid=''
stop_proxy
status disabled
fail_run(){ stop_proxy; printf '0\n' > "$MODDIR/game_enabled"; prepared=0; status "$1"; }
while [ ! -f "$MODDIR/disable" ] && [ ! -f "$MODDIR/remove" ]; do
    enabled=$(cat "$MODDIR/game_enabled" 2>/dev/null)
    if [ "$enabled" != 1 ]; then
        if [ -n "$active_pid" ] || [ "$prepared" = 1 ]; then stop_proxy; status disabled; fi
        prepared=0
        break
    fi
    if [ "$prepared" != 1 ]; then
        status preparing_client
        apk=$(pm path "$GAME" 2>/dev/null | sed -n 's/^package://p' | head -n 1)
        uid=$(cmd package list packages -U "$GAME" 2>/dev/null | sed -n 's/^package:com\.miniworldroyale\.sparkgame uid:\([0-9][0-9]*\)$/\1/p')
        case "$uid" in ''|*[!0-9]*) fail_run game_uid_unavailable; continue;; esac
        [ "$uid" -ge 10000 ] && [ -r "$apk" ] || { fail_run game_apk_unavailable; continue; }
        if ! "$BIN" prepare --apk "$apk" --state "$STATE" > "$STATE/prepare.txt" 2>&1; then fail_run client_prepare_failed; continue; fi
        if ! sh "$MODDIR/trust.sh" prepare > "$STATE/trust-prepare.txt" 2>&1; then fail_run certificate_prepare_failed; continue; fi
        prepared=1
        status waiting_game
    fi
    [ "$(cat "$MODDIR/game_enabled" 2>/dev/null)" = 1 ] || { status disabled; break; }
    set -- $(pidof "$GAME" 2>/dev/null)
    game_pid=${1:-}
    if [ -n "$active_pid" ] && [ "$game_pid" != "$active_pid" ]; then stop_proxy; status waiting_game; fi
    if [ -n "$game_pid" ] && [ -z "$active_pid" ]; then
        status preparing_game_namespace
        if ! sh "$MODDIR/trust.sh" mount "$game_pid" > "$STATE/trust-mount.txt" 2>&1; then fail_run certificate_mount_failed; continue; fi
        rm -f "$STATE/ready" "$STATE/fatal"
        "$BIN" --material-file "$STATE/material" --cert "$STATE/server.pem" --key "$STATE/server.key" \
            --journal "$STATE/events.jsonl" --route-script "$MODDIR/route.sh" --game-uid "$uid" \
            --ready-file "$STATE/ready" --fatal-file "$STATE/fatal" > "$STATE/daemon.txt" 2>&1 &
        proxy_pid=$!
        printf '%s\n' "$proxy_pid" > "$STATE/proxy.pid"
        active_pid=$game_pid
        count=0
        while [ "$count" -lt 40 ] && [ ! -f "$STATE/ready" ] && ours "$proxy_pid"; do sleep 0.5; count=$((count+1)); done
        if [ ! -f "$STATE/ready" ]; then fail_run proxy_start_failed; continue; fi
        status running
    fi
    if [ -n "$active_pid" ]; then
        if [ -f "$STATE/fatal" ]; then
            IFS= read -r code < "$STATE/fatal"
            case "$code" in client_certificate_rejected|original_destination_unavailable|routing_reset_failed) ;; *) code=proxy_process_stopped;; esac
            fail_run "$code"; continue
        fi
        if ! ours "$proxy_pid"; then fail_run proxy_process_stopped; continue; fi
    fi
    if [ -n "$active_pid" ]; then sleep 1; else sleep 0.2; fi
done

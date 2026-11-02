#!/system/bin/sh
MODDIR=${0%/*}
STATE="$MODDIR/state"
BIN="$MODDIR/bin/minifire-external"
GAME=com.miniworldroyale.sparkgame
PREPARE_TIMEOUT=${MINIFIRE_PREPARE_TIMEOUT:-90}
case "$PREPARE_TIMEOUT" in ''|*[!0-9]*) PREPARE_TIMEOUT=90;; esac
[ "$PREPARE_TIMEOUT" -ge 1 ] && [ "$PREPARE_TIMEOUT" -le 300 ] || PREPARE_TIMEOUT=90
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
controller_alive(){
    case "$1" in ''|*[!0-9]*) return 1;; esac
    [ -r "/proc/$1/cmdline" ] || return 1
    controller_command=$(tr '\000' ' ' < "/proc/$1/cmdline")
    case "$controller_command" in *"$MODDIR/controller.sh"*) return 0;; esac
    return 1
}
worker_owned(){
    [ -f "$STATE/worker.pid" ] || return 1
    read -r worker_pid worker_parent worker_start < "$STATE/worker.pid"
    case "$worker_pid:$worker_parent:$worker_start" in *[!0-9:]*|::*|:*) return 1;; esac
    [ "$worker_parent" = "$1" ] && [ -r "/proc/$worker_pid/status" ] || return 1
    [ "$(awk '/^PPid:/ {print $2}' "/proc/$worker_pid/status" 2>/dev/null)" = "$worker_parent" ] &&
    [ "$(awk '{print $22}' "/proc/$worker_pid/stat" 2>/dev/null)" = "$worker_start" ]
}
stop_worker(){
    if worker_owned "$1"; then
        kill "$worker_pid" 2>/dev/null || :
        worker_wait=0
        while [ "$worker_wait" -lt 10 ] && worker_owned "$1"; do sleep 0.1; worker_wait=$((worker_wait+1)); done
        if worker_owned "$1"; then kill -9 "$worker_pid" 2>/dev/null || :; fi
        wait "$worker_pid" 2>/dev/null || :
    fi
    rm -f "$STATE/worker.pid"
}
bounded_step(){
    step_limit=$1; step_stage=$2; step_log=$3; shift 3
    status "$step_stage"
    "$@" > "$step_log" 2>&1 &
    step_pid=$!
    step_start=$(awk '{print $22}' "/proc/$step_pid/stat" 2>/dev/null)
    printf '%s %s %s\n' "$step_pid" "$$" "$step_start" > "$STATE/worker.pid"
    step_ticks=0
    while kill -0 "$step_pid" 2>/dev/null; do
        if [ "$(cat "$MODDIR/game_enabled" 2>/dev/null)" != 1 ] || [ -f "$MODDIR/disable" ] || [ -f "$MODDIR/remove" ]; then
            stop_worker "$$"; return 125
        fi
        if [ "$step_ticks" -ge "$((step_limit*5))" ]; then
            stop_worker "$$"; printf 'step_timeout\n' >> "$step_log"; return 124
        fi
        if [ "$step_stage" = preparing_client ] && [ -f "$STATE/prepare-progress" ]; then
            progress=$(cat "$STATE/prepare-progress")
            case "$progress" in reading_apk_binary|reading_apk_metadata|verifying_client_binary|preparing_local_certificate|saving_local_material)
                if [ "$progress" != "$stage" ]; then status "$progress"; fi;;
            esac
        fi
        sleep 0.2; step_ticks=$((step_ticks+1))
    done
    wait "$step_pid"; step_exit=$?
    rm -f "$STATE/worker.pid"
    return "$step_exit"
}
stop_proxy(){
    cleanup_result=0
    # Restore connectivity before stopping the listener. Keep failure evidence.
    if [ -f "$STATE/cleanup.txt" ] && [ "$(wc -c < "$STATE/cleanup.txt")" -gt 65536 ]; then tail -n 100 "$STATE/cleanup.txt" > "$STATE/cleanup.tmp"; mv -f "$STATE/cleanup.tmp" "$STATE/cleanup.txt"; fi
    printf '\n[cleanup %s]\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$STATE/cleanup.txt"
    sh "$MODDIR/route.sh" stop >> "$STATE/cleanup.txt" 2>&1 || cleanup_result=1
    if [ -f "$STATE/proxy.pid" ]; then
        IFS= read -r proxy_pid < "$STATE/proxy.pid"
        if ours "$proxy_pid"; then
            kill "$proxy_pid" 2>/dev/null || :
            count=0
            while [ "$count" -lt 20 ] && ours "$proxy_pid"; do sleep 0.2; count=$((count+1)); done
            if ours "$proxy_pid"; then kill -9 "$proxy_pid" 2>/dev/null || :; fi
        fi
    fi
    sh "$MODDIR/trust.sh" unmount >> "$STATE/cleanup.txt" 2>&1 || cleanup_result=1
    rm -f "$STATE/proxy.pid" "$STATE/ready" "$STATE/fatal"
    active_pid=''
    return "$cleanup_result"
}
if [ "$1" = stop ]; then
    printf '0\n' > "$MODDIR/game_enabled"
    stop_owner=''
    [ ! -f "$STATE/controller.lock/pid" ] || IFS= read -r stop_owner < "$STATE/controller.lock/pid"
    if [ "$stop_owner" != "$$" ] && controller_alive "$stop_owner"; then
        stop_worker "$stop_owner"
        kill "$stop_owner" 2>/dev/null || :
        stop_wait=0
        while [ "$stop_wait" -lt 30 ] && controller_alive "$stop_owner"; do sleep 0.1; stop_wait=$((stop_wait+1)); done
        if controller_alive "$stop_owner"; then kill -9 "$stop_owner" 2>/dev/null || :; fi
    fi
    if stop_proxy; then status disabled; else status cleanup_failed; exit 1; fi
    rm -f "$STATE/controller.lock/pid"
    rmdir "$STATE/controller.lock" 2>/dev/null || :
    exit 0
fi
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
cleanup(){ stop_worker "$$"; stop_proxy || status cleanup_failed; rm -f "$STATE/controller.lock/pid"; rmdir "$STATE/controller.lock" 2>/dev/null || :; }
trap 'cleanup' EXIT
trap 'exit 0' INT TERM HUP
prepared=0
active_pid=''
if ! stop_proxy; then printf '0\n' > "$MODDIR/game_enabled"; status cleanup_failed; exit 1; fi
status disabled
fail_run(){ printf '0\n' > "$MODDIR/game_enabled"; prepared=0; if stop_proxy; then status "$1"; else status cleanup_failed; fi; }
while [ ! -f "$MODDIR/disable" ] && [ ! -f "$MODDIR/remove" ]; do
    enabled=$(cat "$MODDIR/game_enabled" 2>/dev/null)
    if [ "$enabled" != 1 ]; then
        if [ -n "$active_pid" ] || [ "$prepared" = 1 ]; then stop_proxy; status disabled; fi
        prepared=0
        break
    fi
    if [ "$prepared" != 1 ]; then
        bounded_step 15 locating_game "$STATE/package-path.txt" pm path "$GAME"; step_code=$?
        if [ "$step_code" = 125 ]; then status disabled; break; fi
        [ "$step_code" = 0 ] || { fail_run package_lookup_failed; continue; }
        bounded_step 15 locating_game_uid "$STATE/package-uid.txt" cmd package list packages -U "$GAME"; step_code=$?
        if [ "$step_code" = 125 ]; then status disabled; break; fi
        [ "$step_code" = 0 ] || { fail_run package_lookup_failed; continue; }
        apk=$(sed -n 's/^package://p' "$STATE/package-path.txt" | head -n 1)
        uid=$(sed -n 's/^package:com\.miniworldroyale\.sparkgame uid:\([0-9][0-9]*\)$/\1/p' "$STATE/package-uid.txt")
        case "$uid" in ''|*[!0-9]*) fail_run game_uid_unavailable; continue;; esac
        [ "$uid" -ge 10000 ] && [ -r "$apk" ] || { fail_run game_apk_unavailable; continue; }
        rm -f "$STATE/prepare-progress"
        bounded_step "$PREPARE_TIMEOUT" preparing_client "$STATE/prepare.txt" "$BIN" prepare --apk "$apk" --state "$STATE"; step_code=$?
        if [ "$step_code" = 125 ]; then status disabled; break; fi
        if [ "$step_code" = 124 ]; then fail_run client_prepare_timeout; continue; fi
        [ "$step_code" = 0 ] || { fail_run client_prepare_failed; continue; }
        bounded_step 30 preparing_trust_store "$STATE/trust-prepare.txt" sh "$MODDIR/trust.sh" prepare; step_code=$?
        if [ "$step_code" = 125 ]; then status disabled; break; fi
        [ "$step_code" = 0 ] || { fail_run certificate_prepare_failed; continue; }
        prepared=1
        status waiting_game
    fi
    [ "$(cat "$MODDIR/game_enabled" 2>/dev/null)" = 1 ] || { status disabled; break; }
    set -- $(pidof "$GAME" 2>/dev/null)
    game_pid=${1:-}
    if [ -n "$active_pid" ] && [ "$game_pid" != "$active_pid" ]; then stop_proxy; status waiting_game; fi
    if [ -n "$game_pid" ] && [ -z "$active_pid" ]; then
        status preparing_game_namespace
        bounded_step 15 preparing_game_namespace "$STATE/trust-mount.txt" sh "$MODDIR/trust.sh" mount "$game_pid"; step_code=$?
        if [ "$step_code" = 125 ]; then status disabled; break; fi
        [ "$step_code" = 0 ] || { fail_run certificate_mount_failed; continue; }
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

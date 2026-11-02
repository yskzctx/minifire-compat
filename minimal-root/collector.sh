#!/system/bin/sh
MODDIR=${0%/*}
STATE="$MODDIR/state"
mkdir -p "$STATE" && chmod 0700 "$STATE" || exit 1
printf '%s\n' "$$" > "$STATE/collector.pid"
child=''
stop_child(){
    case "$child" in ''|*[!0-9]*) return;; esac
    if [ -r "/proc/$child/cmdline" ]; then
        command=$(tr '\000' ' ' < "/proc/$child/cmdline")
        case "$command" in *logcat*"$STATE/system-module.log"*) kill "$child" 2>/dev/null || :;; esac
    fi
    wait "$child" 2>/dev/null || :
}
trap 'stop_child; exit 0' INT TERM HUP
attempt=0
while [ ! -f "$MODDIR/disable" ] && [ ! -f "$MODDIR/remove" ] && [ ! -f "$STATE/collector.stop" ]; do
    if [ -f "$STATE/collector-error.txt" ] && [ "$(wc -c < "$STATE/collector-error.txt")" -gt 32768 ]; then
        tail -n 120 "$STATE/collector-error.txt" > "$STATE/collector-error.tmp"
        mv -f "$STATE/collector-error.tmp" "$STATE/collector-error.txt"
    fi
    attempt=$((attempt+1))
    printf '\n[collector %s attempt=%s]\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$attempt" >> "$STATE/collector-error.txt"
    logcat -b main -T 1 -v threadtime -f "$STATE/system-module.log" -r 1024 -n 2 -s MinifireCompatM:I '*:S' 2>> "$STATE/collector-error.txt" &
    child=$!
    printf '%s\n' "$child" > "$STATE/collector-child.pid"
    wait "$child"; code=$?
    printf 'collector_exit=%s\n' "$code" >> "$STATE/collector-error.txt"
    child=''
    [ ! -f "$STATE/collector.stop" ] || break
    sleep 2
done

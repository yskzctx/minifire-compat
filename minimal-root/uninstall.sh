#!/system/bin/sh
MODDIR=${0%/*}
# Existing game processes keep their startup configuration until they exit.
printf '0' | dd of="$MODDIR/game_enabled" bs=1 count=1 conv=notrunc 2>/dev/null
mkdir -p "$MODDIR/state"
touch "$MODDIR/state/collector.stop"
if [ -f "$MODDIR/state/collector.pid" ]; then
    IFS= read -r collector < "$MODDIR/state/collector.pid"
    case "$collector" in ''|*[!0-9]*) exit 0;; esac
    command=$(tr '\000' ' ' < "/proc/$collector/cmdline" 2>/dev/null)
    case "$command" in *"$MODDIR/collector.sh"*) kill "$collector" 2>/dev/null || :;; esac
fi

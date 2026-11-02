#!/system/bin/sh
MODDIR=${0%/*}
# Running games retain the passthrough trampoline until they exit. Do not unhook
# executable code concurrently with Lua or remove another module's network rules.
printf '0' | dd of="$MODDIR/game_enabled" bs=1 count=1 conv=notrunc 2>/dev/null
if [ -f "$MODDIR/state/collector.pid" ]; then
    IFS= read -r collector < "$MODDIR/state/collector.pid"
    case "$collector" in ''|*[!0-9]*) exit 0;; esac
    command=$(tr '\000' ' ' < "/proc/$collector/cmdline" 2>/dev/null)
    case "$command" in *logcat*"$MODDIR/state/system-module.log"*) kill "$collector" 2>/dev/null || :;; esac
fi

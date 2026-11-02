#!/system/bin/sh
MODDIR=${0%/*}
while [ "$(getprop sys.boot_completed)" != 1 ]; do sleep 2; done
[ "$(cat "$MODDIR/game_enabled" 2>/dev/null)" = 1 ] || exit 0
exec sh "$MODDIR/controller.sh"

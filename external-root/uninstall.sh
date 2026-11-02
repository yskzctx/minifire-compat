#!/system/bin/sh
MODDIR=${0%/*}
printf '0\n' > "$MODDIR/game_enabled"
sh "$MODDIR/controller.sh" stop

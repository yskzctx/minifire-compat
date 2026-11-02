#!/system/bin/sh
MODDIR=${0%/*}
mkdir -p "$MODDIR/state" && chmod 0700 "$MODDIR/state" || exit 1
printf 'method=single_pb_encode_hook\nproxy=not_used\ncertificate_mounts=not_used\nlsposed=not_required\n' > "$MODDIR/state/boot.txt"
rm -f "$MODDIR/state/collector.stop"
exec sh "$MODDIR/collector.sh"

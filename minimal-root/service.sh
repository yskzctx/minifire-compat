#!/system/bin/sh
MODDIR=${0%/*}
mkdir -p "$MODDIR/state" && chmod 0700 "$MODDIR/state" || exit 1
printf 'method=single_pb_encode_hook\nproxy=not_used\ncertificate_mounts=not_used\nlsposed=not_required\n' > "$MODDIR/state/boot.txt"
# A Root logcat collector preserves module-tag logs even when SELinux refuses
# an app's inherited log FD. This collector never changes SELinux policy.
printf '%s\n' "$$" > "$MODDIR/state/collector.pid"
exec logcat -T 1 -v threadtime -f "$MODDIR/state/system-module.log" -r 1024 -n 2 -s MinifireCompatM:I '*:S' 2> "$MODDIR/state/collector-error.txt"

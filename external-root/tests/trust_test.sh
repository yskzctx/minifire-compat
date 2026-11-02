#!/usr/bin/env bash
set -eu
fixture=$(mktemp -d)
case "$fixture" in */tmp.*) ;; *) exit 1;; esac
cleanup(){ rm -f "$fixture/trust.sh" "$fixture/nsenter" "$fixture/readlink" "$fixture/calls" "$fixture/proc/1/ns/mnt" "$fixture/proc/123/ns/mnt" "$fixture/proc/123/cmdline" "$fixture/proc/123/mountinfo" "$fixture/state/trust_ready" "$fixture/state/trust-error.txt" "$fixture/state/mount_pid" "$fixture/state/mount_ns" "$fixture/state/mount_targets"; rmdir "$fixture/state" "$fixture/proc/1/ns" "$fixture/proc/1" "$fixture/proc/123/ns" "$fixture/proc/123" "$fixture/proc" "$fixture" 2>/dev/null || :; }
trap cleanup EXIT
trap 'rm -f "$fixture/config.sh" "$fixture/target_package" "$fixture/state/mount_package"; cleanup' EXIT
trap 'rm -f "$fixture/config.sh" "$fixture/target_package" "$fixture/state/mount_package"; rmdir "$fixture/apex" 2>/dev/null || :; cleanup' EXIT
cp external-root/trust.sh "$fixture/trust.sh"
cp external-root/config.sh "$fixture/config.sh"
mkdir -p "$fixture/proc/1/ns" "$fixture/proc/123/ns"
printf 'mnt:[100]\n' > "$fixture/proc/1/ns/mnt"
printf 'mnt:[100]\n' > "$fixture/proc/123/ns/mnt"
printf '#!/bin/sh\nif [ -f "$1" ]; then cat "$1"; else printf "mnt:[300]\\n"; fi\n' > "$fixture/readlink"
chmod +x "$fixture/readlink"
PATH="$fixture:/usr/bin:/bin:$PATH"
printf 'com.miniworldroyale.sparkgame\0' > "$fixture/proc/123/cmdline"
cat > "$fixture/nsenter" <<'SH'
#!/bin/sh
printf 'called\n' >> "$CALLS"
SH
chmod +x "$fixture/nsenter"
export MINIFIRE_PROC="$fixture/proc" MINIFIRE_NSENTER="$fixture/nsenter" CALLS="$fixture/calls"
if output=$(sh "$fixture/trust.sh" mount 123); then exit 1; fi
[ "$output" = shared_mount_namespace ]
[ ! -f "$fixture/calls" ]
echo 'shared game namespace is rejected before any mount operation'
printf 'com.example.minifire.channel\n' > "$fixture/target_package"
printf 'com.example.minifire.channel\0' > "$fixture/proc/123/cmdline"
if output=$(sh "$fixture/trust.sh" mount 123); then exit 1; fi
[ "$output" = shared_mount_namespace ]
rm -f "$fixture/target_package"
printf 'com.miniworldroyale.sparkgame\0' > "$fixture/proc/123/cmdline"
echo 'selected package is used for process identity checks'
mkdir "$fixture/state"
touch "$fixture/state/trust_ready"
printf 'mnt:[200]\n' > "$fixture/proc/123/ns/mnt"
cat > "$fixture/nsenter" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$CALLS"
exit 1
SH
if output=$(sh "$fixture/trust.sh" mount 123); then exit 1; fi
[ "$output" = target_mount_propagation_failed ]
grep -q -- 'namespace-private --expected-namespace mnt:\[200\]' "$CALLS"
if grep -q -- 'mount --make-rprivate' "$CALLS"; then exit 1; fi
if grep -q -- 'mount --bind' "$CALLS"; then exit 1; fi
echo 'mount propagation must be private before binding certificates'
printf '123\n' > "$fixture/state/mount_pid"
printf 'mnt:[200]\n' > "$fixture/state/mount_ns"
printf '/system/etc/security/cacerts\n' > "$fixture/state/mount_targets"
printf '1 2 0:1 /adb/modules/minifire_compat_zygisk/state/trust /system/etc/security/cacerts rw - ext4 /dev/test rw\n' > "$fixture/proc/123/mountinfo"
if sh "$fixture/trust.sh" unmount; then echo 'failed unmount was reported as success' >&2; exit 1; fi
[ -f "$fixture/state/mount_pid" ]
[ -f "$fixture/state/mount_targets" ]
echo 'failed unmount reports failure and keeps recovery records'
rm -f "$fixture/state/mount_pid" "$fixture/state/mount_ns" "$fixture/state/mount_targets" "$fixture/state/mount_package"
mkdir "$fixture/apex"
export MINIFIRE_TRUST_APEX="$fixture/apex" MINIFIRE_TRUST_SYSTEM="$fixture/absent"
: > "$CALLS"
cat > "$fixture/nsenter" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$CALLS"
case " $* " in
 *' mount --make-rprivate '*) printf 'mount: bad /etc/fstab: No such file or directory\n' >&2; exit 1;;
 *' namespace-private '*) printf 'namespace_private_syscall_ok\n'; exit 0;;
 *' mount --bind '*) exit 0;;
 *) exit 1;;
esac
SH
output=$(sh "$fixture/trust.sh" mount 123)
printf '%s\n' "$output" | grep -q namespace_private_syscall_ok
printf '%s\n' "$output" | grep -q '^mounted$'
grep -q 'mount --bind' "$CALLS"
if grep -q 'mount --make-rprivate' "$CALLS"; then exit 1; fi
echo 'namespace helper permits bind setup without unsupported mount long options'

#!/usr/bin/env bash
set -eu
fixture=$(mktemp -d)
case "$fixture" in */tmp.*) ;; *) exit 1;; esac
cleanup(){ rm -f "$fixture/trust.sh" "$fixture/nsenter" "$fixture/readlink" "$fixture/calls" "$fixture/proc/1/ns/mnt" "$fixture/proc/123/ns/mnt" "$fixture/proc/123/cmdline" "$fixture/state/trust_ready" "$fixture/state/trust-error.txt"; rmdir "$fixture/state" "$fixture/proc/1/ns" "$fixture/proc/1" "$fixture/proc/123/ns" "$fixture/proc/123" "$fixture/proc" "$fixture" 2>/dev/null || :; }
trap cleanup EXIT
cp external-root/trust.sh "$fixture/trust.sh"
mkdir -p "$fixture/proc/1/ns" "$fixture/proc/123/ns"
printf 'mnt:[100]\n' > "$fixture/proc/1/ns/mnt"
printf 'mnt:[100]\n' > "$fixture/proc/123/ns/mnt"
printf '#!/bin/sh\ncat "$1"\n' > "$fixture/readlink"
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
grep -q -- 'mount --make-rprivate /' "$CALLS"
if grep -q -- 'mount --bind' "$CALLS"; then exit 1; fi
echo 'mount propagation must be private before binding certificates'

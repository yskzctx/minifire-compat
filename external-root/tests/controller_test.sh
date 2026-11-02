#!/usr/bin/env bash
set -eu
fixture=$(mktemp -d)
case "$fixture" in */tmp.*) ;; *) exit 1;; esac
cleanup(){
 rm -f "$fixture/config.sh" "$fixture/target_package"
 [ -z "${controller_pid:-}" ] || kill "$controller_pid" 2>/dev/null || :
 rm -f "$fixture/controller.sh" "$fixture/route.sh" "$fixture/trust.sh" "$fixture/game_enabled" "$fixture/game.apk" "$fixture/calls" "$fixture/bin/minifire-external" "$fixture/tools/pm" "$fixture/tools/cmd" "$fixture/state/status" "$fixture/state/controller.jsonl" "$fixture/state/prepare.txt" "$fixture/state/prepare-progress" "$fixture/state/worker.pid" "$fixture/state/cleanup.txt" "$fixture/state/package-files.txt" "$fixture/state/package-path.txt" "$fixture/state/package-uid.txt" "$fixture/state/controller.lock/pid"
 rmdir "$fixture/state/controller.lock" "$fixture/bin" "$fixture/tools" "$fixture/state" "$fixture" 2>/dev/null || :
}
trap cleanup EXIT
mkdir "$fixture/bin" "$fixture/tools"
cp external-root/controller.sh "$fixture/controller.sh"
cp external-root/config.sh "$fixture/config.sh"
printf '#!/bin/sh\nprintf "route %%s\\n" "$*" >> "$CALLS"\n' > "$fixture/route.sh"
printf '#!/bin/sh\nprintf "trust %%s\\n" "$*" >> "$CALLS"\n' > "$fixture/trust.sh"
cat > "$fixture/bin/minifire-external" <<'SH'
#!/bin/sh
if [ "$1" = locate ]; then
 if [ "${FIXTURE_LOCATE_FAIL:-0}" = 1 ]; then printf 'installed_apk_ambiguous\n'; exit 1; fi
 printf 'apk=%s\nuid=10240\nsource=fixture\n' "$TEST_APK"; exit 0
fi
printf 'prepare\n' >> "$CALLS"
printf 'client_binary_unrecognized\n'
exit 1
SH
cat > "$fixture/tools/pm" <<'SH'
#!/bin/sh
printf 'binder_invoked\n' >> "$CALLS"
if [ "${FIXTURE_BINDER_OK:-0}" = 1 ]; then
 case "$0" in */pm) printf 'package:%s\n' "$TEST_APK";; *) printf 'package:com.miniworldroyale.sparkgame uid:10240\n';; esac
 exit 0
fi
printf 'cmd: Failure calling service package: Failed transaction (2147483646)\n' >&2
exit 1
SH
cp "$fixture/tools/pm" "$fixture/tools/cmd"
chmod +x "$fixture/bin/minifire-external" "$fixture/tools/pm" "$fixture/tools/cmd"
touch "$fixture/game.apk"
export CALLS="$fixture/calls" TEST_APK="$fixture/game.apk"
PATH="$fixture/tools:/usr/bin:/bin:$PATH"
printf '0\n' > "$fixture/game_enabled"
timeout 5 sh "$fixture/controller.sh"
[ ! -d "$fixture/state/controller.lock" ]
if grep -q '^prepare$' "$CALLS"; then exit 1; fi
printf '1\n' > "$fixture/game_enabled"
timeout 5 sh "$fixture/controller.sh"
[ "$(cat "$fixture/game_enabled")" = 0 ]
[ "$(cat "$fixture/state/status")" = client_not_supported ]
grep -q client_binary_unrecognized "$fixture/state/prepare.txt"
if grep -q binder_invoked "$CALLS"; then echo 'unnecessary broken Binder lookup' >&2; exit 1; fi
if grep -q '^trust mount\|^route init' "$CALLS"; then exit 1; fi
echo 'disabled controller exits and unknown client stops before certificate mounts or routing'
export FIXTURE_LOCATE_FAIL=1 FIXTURE_BINDER_OK=1
printf '1\n' > "$fixture/game_enabled"
timeout 5 sh "$fixture/controller.sh"
[ "$(cat "$fixture/state/status")" = client_not_supported ]
grep -q binder_invoked "$CALLS"
unset FIXTURE_BINDER_OK
printf '1\n' > "$fixture/game_enabled"
timeout 5 sh "$fixture/controller.sh"
[ "$(cat "$fixture/state/status")" = package_lookup_failed ]
grep -q installed_apk_ambiguous "$fixture/state/package-files.txt"
grep -q 'Failed transaction' "$fixture/state/package-path.txt"
unset FIXTURE_LOCATE_FAIL
echo 'Binder is only a fallback and both lookup failures remain in diagnostics'
cat > "$fixture/bin/minifire-external" <<'SH'
#!/bin/sh
if [ "$1" = locate ]; then printf 'apk=%s\nuid=10240\nsource=fixture\n' "$TEST_APK"; exit 0; fi
printf 'blocked_prepare\n' >> "$CALLS"
exec sleep 30
SH
printf '1\n' > "$fixture/game_enabled"
sh "$fixture/controller.sh" &
controller_pid=$!
count=0
while ! grep -q blocked_prepare "$CALLS" && [ "$count" -lt 30 ]; do sleep 0.1; count=$((count+1)); done
grep -q blocked_prepare "$CALLS"
printf '0\n' > "$fixture/game_enabled"
count=0
while kill -0 "$controller_pid" 2>/dev/null && [ "$count" -lt 30 ]; do sleep 0.1; count=$((count+1)); done
if kill -0 "$controller_pid" 2>/dev/null; then echo 'blocked prepare ignored disable' >&2; exit 1; fi
wait "$controller_pid"
controller_pid=''
[ ! -f "$fixture/state/worker.pid" ]
[ ! -d "$fixture/state/controller.lock" ]
[ "$(cat "$fixture/state/status")" = disabled ]
echo 'turning off cancels a blocked prepare worker and releases its controller'
printf '1\n' > "$fixture/game_enabled"
MINIFIRE_PREPARE_TIMEOUT=1 timeout 8 sh "$fixture/controller.sh"
[ "$(cat "$fixture/state/status")" = client_prepare_timeout ]
[ "$(cat "$fixture/game_enabled")" = 0 ]
[ ! -f "$fixture/state/worker.pid" ]
grep -q step_timeout "$fixture/state/prepare.txt"
echo 'blocked preparation times out and disables without routing'
printf '1\n' > "$fixture/game_enabled"
sh "$fixture/controller.sh" &
controller_pid=$!
count=0
while [ ! -f "$fixture/state/worker.pid" ] && [ "$count" -lt 30 ]; do sleep 0.1; count=$((count+1)); done
timeout 8 sh "$fixture/controller.sh" stop
wait "$controller_pid"
controller_pid=''
[ "$(cat "$fixture/state/status")" = disabled ]
[ ! -f "$fixture/state/worker.pid" ]
[ ! -d "$fixture/state/controller.lock" ]
echo 'explicit stop terminates its controller and worker safely'
cat > "$fixture/route.sh" <<'SH'
#!/bin/sh
printf 'fixture_route_cleanup_error\n'
exit 1
SH
if sh "$fixture/controller.sh" stop; then echo 'cleanup error hidden' >&2; exit 1; fi
[ "$(cat "$fixture/state/status")" = cleanup_failed ]
grep -q fixture_route_cleanup_error "$fixture/state/cleanup.txt"
echo 'cleanup failure remains visible after the switch is off'

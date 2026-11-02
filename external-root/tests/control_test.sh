#!/usr/bin/env bash
set -eu
fixture=$(mktemp -d)
cleanup(){ rm -f "$fixture/config.sh" "$fixture/target_package" "$fixture/state/target-error.txt" "$fixture/bin/minifire-external" "$fixture/control.sh" "$fixture/controller.sh" "$fixture/game_enabled" "$fixture/calls"; rmdir "$fixture/state" "$fixture/bin" "$fixture" 2>/dev/null || :; }
trap cleanup EXIT
cp external-root/control.sh "$fixture/control.sh"
cp external-root/config.sh "$fixture/config.sh"
mkdir "$fixture/bin"
cat > "$fixture/bin/minifire-external" <<'SH'
#!/bin/sh
if [ "$1" = target ] && [ "$3" = com.example.minifire.channel ]; then printf '%s\n' "$3"; else exit 1; fi
SH
chmod +x "$fixture/bin/minifire-external"
cat > "$fixture/controller.sh" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$CALLS"
SH
export CALLS="$fixture/calls"
printf '1\n' > "$fixture/game_enabled"
[ "$(sh "$fixture/control.sh" game 0)" = 0 ]
grep -qx stop "$CALLS"
echo 'turning off explicitly runs synchronous cleanup'
[ "$(sh "$fixture/control.sh" target com.example.minifire.channel)" = com.example.minifire.channel ]
[ "$(cat "$fixture/target_package")" = com.example.minifire.channel ]
status_result=$(sh "$fixture/control.sh" status)
printf '%s\n' "$status_result" | grep -q '^target=com.example.minifire.channel$'
if sh "$fixture/control.sh" target 'com.app;id'; then exit 1; fi
[ "$(cat "$fixture/target_package")" = com.example.minifire.channel ]
echo 'selected target is validated and saved after cleanup'
printf 'kernel=errno=92; proc=fixture_permission_denied\n' > "$fixture/state/destination-error.txt"
diagnostic=$(sh "$fixture/control.sh" logs)
printf '%s\n' "$diagnostic" | grep -q '^\[destination-error.txt\]$'
printf '%s\n' "$diagnostic" | grep -q 'kernel=errno=92; proc=fixture_permission_denied'
rm -f "$fixture/state/destination-error.txt"
echo 'original destination failure details are readable through control logs'

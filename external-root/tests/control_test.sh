#!/usr/bin/env bash
set -eu
fixture=$(mktemp -d)
cleanup(){ rm -f "$fixture/control.sh" "$fixture/controller.sh" "$fixture/game_enabled" "$fixture/calls"; rmdir "$fixture" 2>/dev/null || :; }
trap cleanup EXIT
cp external-root/control.sh "$fixture/control.sh"
cat > "$fixture/controller.sh" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$CALLS"
SH
export CALLS="$fixture/calls"
printf '1\n' > "$fixture/game_enabled"
[ "$(sh "$fixture/control.sh" game 0)" = 0 ]
grep -qx stop "$CALLS"
echo 'turning off explicitly runs synchronous cleanup'

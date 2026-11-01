#!/usr/bin/env bash
set -eu
fixture=$(mktemp -d)
case "$fixture" in */tmp.*) ;; *) echo 'unexpected temporary path' >&2; exit 1;; esac
trap 'rm -f "$fixture/game_enabled" "$fixture/hunter_enabled"; rmdir "$fixture"' EXIT
MODPATH=$fixture
set_perm() { :; }
abort() { echo "$*" >&2; exit 1; }
. zygisk-root/customize.sh
[ "$(cat "$MODPATH/game_enabled")" = 0 ]
[ "$(cat "$MODPATH/hunter_enabled")" = 0 ]
printf '1\n' > "$MODPATH/game_enabled"
rm "$MODPATH/hunter_enabled"
. zygisk-root/customize.sh
[ "$(cat "$MODPATH/game_enabled")" = 1 ]
[ "$(cat "$MODPATH/hunter_enabled")" = 0 ]
printf '1\n' > "$MODPATH/hunter_enabled"
. zygisk-root/customize.sh
[ "$(cat "$MODPATH/game_enabled")" = 1 ]
[ "$(cat "$MODPATH/hunter_enabled")" = 1 ]
echo 'installer flag initialization and preservation ok'

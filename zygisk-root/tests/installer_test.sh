#!/usr/bin/env bash
set -eu
fixture=$(mktemp -d)
case "$fixture" in */tmp.*) ;; *) echo 'unexpected temporary path' >&2; exit 1;; esac
trap 'rm -f "$fixture/game_enabled" "$fixture/hunter_enabled" "$fixture/old/game_enabled" "$fixture/old/hunter_enabled" "$fixture/new/game_enabled" "$fixture/new/hunter_enabled"; rmdir "$fixture/old" "$fixture/new" "$fixture" 2>/dev/null || :' EXIT
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
mkdir "$fixture/old" "$fixture/new"
printf '1\n' > "$fixture/old/game_enabled"
printf '0\n' > "$fixture/old/hunter_enabled"
printf '0\n' > "$fixture/new/game_enabled"
printf '0\n' > "$fixture/new/hunter_enabled"
MINIFIRE_INSTALLED_DIR="$fixture/old"
MODPATH="$fixture/new"
. zygisk-root/customize.sh
[ "$(cat "$MODPATH/game_enabled")" = 1 ]
[ "$(cat "$MODPATH/hunter_enabled")" = 0 ]

echo 'installer flag initialization and update preservation ok'

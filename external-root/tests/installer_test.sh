#!/usr/bin/env bash
set -eu
fixture=$(mktemp -d)
case "$fixture" in */tmp.*) ;; *) exit 1;; esac
trap 'rm -f "$fixture/game_enabled" "$fixture/bin/minifire-external" "$fixture/keep"; rmdir "$fixture/bin" "$fixture" 2>/dev/null || :' EXIT
mkdir -p "$fixture/zygisk" "$fixture/lib/arm64-v8a" "$fixture/bin"
printf old > "$fixture/zygisk/arm64-v8a.so"
printf old > "$fixture/lib/arm64-v8a/libminifire_core.so"
printf fixture > "$fixture/bin/minifire-external"
printf keep > "$fixture/keep"
MODPATH=$fixture
set_perm(){ :; };ui_print(){ :; };abort(){ exit 1; }
. external-root/customize.sh
[ "$(cat "$fixture/game_enabled")" = 0 ]
[ ! -e "$fixture/zygisk/arm64-v8a.so" ]
[ ! -e "$fixture/lib/arm64-v8a/libminifire_core.so" ]
[ "$(cat "$fixture/keep")" = keep ]
echo 'migration removes old injection payload and preserves unrelated files'

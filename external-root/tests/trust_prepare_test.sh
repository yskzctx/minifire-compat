#!/usr/bin/env bash
set -eu
fixture=$(mktemp -d)
mod="$fixture/minifire_compat_zygisk"
cleanup(){
 rm -f "$mod/trust.sh" "$mod/config.sh" "$mod/state/ca.pem" "$mod/state/ca.key" "$mod/state/material" "$mod/state/ca-filename" "$mod/state/trust_ready" "$fixture/base/12345678.0" "$fixture/cache/trust/12345678.0" "$fixture/cache/trust/deadbeef.0" "$fixture/tools/ls" "$fixture/tools/chcon" "$fixture/tools/stat"
 rmdir "$fixture/cache/trust" "$fixture/cache" "$mod/state" "$mod" "$fixture/base" "$fixture/tools" "$fixture" 2>/dev/null || :
}
trap cleanup EXIT
mkdir -p "$mod/state" "$fixture/base" "$fixture/tools"
cp external-root/trust.sh "$mod/trust.sh"
cp external-root/config.sh "$mod/config.sh"
printf 'PUBLIC LOCAL CA\n' > "$mod/state/ca.pem"
printf 'PRIVATE KEY MUST NOT STAGE\n' > "$mod/state/ca.key"
printf 'PRIVATE MATERIAL MUST NOT STAGE\n' > "$mod/state/material"
printf 'deadbeef.0\n' > "$mod/state/ca-filename"
printf 'ORIGINAL SYSTEM CA\n' > "$fixture/base/12345678.0"
printf '#!/bin/sh\nprintf "u:object_r:system_security_cacerts_file:s0 fixture\\n"\n' > "$fixture/tools/ls"
printf '#!/bin/sh\nexit 0\n' > "$fixture/tools/chcon"
printf '#!/bin/sh\nprintf "%%s\\n" "${FIXTURE_OWNER:-0}"\n' > "$fixture/tools/stat"
chmod +x "$fixture/tools/ls" "$fixture/tools/chcon" "$fixture/tools/stat"
export MINIFIRE_TRUST_STAGE="$fixture/cache" MINIFIRE_TRUST_APEX="$fixture/base" MINIFIRE_TRUST_SYSTEM="$fixture/absent"
PATH="$fixture/tools:/usr/bin:/bin:$PATH"
sh "$mod/trust.sh" prepare
[ "$(cat "$fixture/cache/trust/deadbeef.0")" = 'PUBLIC LOCAL CA' ]
[ "$(cat "$fixture/cache/trust/12345678.0")" = 'ORIGINAL SYSTEM CA' ]
[ ! -e "$fixture/cache/trust/ca.key" ] && [ ! -e "$fixture/cache/trust/material" ]
sh "$mod/trust.sh" prepare
[ "$(cat "$fixture/cache/trust/deadbeef.0")" = 'PUBLIC LOCAL CA' ]
sh "$mod/trust.sh" clear-cache
[ ! -d "$fixture/cache" ]
[ "$(cat "$mod/state/ca.key")" = 'PRIVATE KEY MUST NOT STAGE' ]
mkdir "$fixture/cache"
if FIXTURE_OWNER=2000 sh "$mod/trust.sh" prepare; then echo 'foreign cache owner accepted' >&2; exit 1; fi
echo 'ordinary-path cache contains only public anchors, survives reprepare, cleans safely and rejects foreign ownership'

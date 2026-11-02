#!/usr/bin/env bash
set -eu
fixture=$(mktemp -d)
case "$fixture" in */tmp.*) ;; *) exit 1;; esac
cleanup(){
 rm -f "$fixture/controller.sh" "$fixture/route.sh" "$fixture/trust.sh" "$fixture/game_enabled" "$fixture/game.apk" "$fixture/calls" "$fixture/bin/minifire-external" "$fixture/tools/pm" "$fixture/tools/cmd" "$fixture/state/status" "$fixture/state/controller.jsonl" "$fixture/state/prepare.txt" "$fixture/state/controller.lock/pid"
 rmdir "$fixture/state/controller.lock" "$fixture/bin" "$fixture/tools" "$fixture/state" "$fixture" 2>/dev/null || :
}
trap cleanup EXIT
mkdir "$fixture/bin" "$fixture/tools"
cp external-root/controller.sh "$fixture/controller.sh"
printf '#!/bin/sh\nprintf "route %%s\\n" "$*" >> "$CALLS"\n' > "$fixture/route.sh"
printf '#!/bin/sh\nprintf "trust %%s\\n" "$*" >> "$CALLS"\n' > "$fixture/trust.sh"
cat > "$fixture/bin/minifire-external" <<'SH'
#!/bin/sh
printf 'prepare\n' >> "$CALLS"
printf 'client_binary_unrecognized\n'
exit 1
SH
printf '#!/bin/sh\nprintf "package:%%s\\n" "$TEST_APK"\n' > "$fixture/tools/pm"
printf '#!/bin/sh\nprintf "package:com.miniworldroyale.sparkgame uid:10240\\n"\n' > "$fixture/tools/cmd"
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
[ "$(cat "$fixture/state/status")" = client_prepare_failed ]
grep -q client_binary_unrecognized "$fixture/state/prepare.txt"
if grep -q '^trust mount\|^route init' "$CALLS"; then exit 1; fi
echo 'disabled controller exits and unknown client stops before certificate mounts or routing'

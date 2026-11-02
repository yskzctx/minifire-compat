#!/system/bin/sh
[ "$ARCH" = arm64 ] || abort 'Only ARM64 Android is supported'
. "$MODPATH/config.sh" || abort 'Missing config helper'
INSTALLED=/data/adb/modules/minifire_compat_zygisk
saved=0; saved_target=$DEFAULT_GAME
if [ -f "$INSTALLED/module.prop" ]; then
    previous=$(head -c 1 "$INSTALLED/game_enabled" 2>/dev/null || :)
    case "$previous" in 0|1) saved=$previous;; esac
    prior_target=$(cat "$INSTALLED/target_package" 2>/dev/null || :)
    valid_package "$prior_target" && saved_target=$prior_target
    old_code=$(sed -n 's/^versionCode=//p' "$INSTALLED/module.prop")
    case "$old_code" in ''|*[!0-9]*) abort 'Invalid installed module version';; esac
    if [ "$old_code" -ge 1000 ] && [ "$old_code" -lt 2000 ]; then
        mkdir -p "$MODPATH/state" && chmod 0700 "$MODPATH/state" || abort 'Cannot prepare private logs'
        ui_print 'Stopping old forwarding and removing its own routes/certificate mounts...'
        sh "$INSTALLED/controller.sh" stop > "$MODPATH/state/migration.txt" 2>&1 || abort 'Old proxy cleanup failed; see existing module diagnostics. Update aborted.'
        printf 'external_proxy_cleanup_success\n' >> "$MODPATH/state/migration.txt"
    fi
fi
printf '%s\n' "$saved" > "$MODPATH/game_enabled" || abort 'Cannot save switch'
printf '%s\n' "$saved_target" > "$MODPATH/target_package" || abort 'Cannot save target'
mkdir -p "$MODPATH/state" && chmod 0700 "$MODPATH/state" || abort 'Cannot initialize logs'
set_perm "$MODPATH/game_enabled" 0 0 0644
set_perm "$MODPATH/target_package" 0 0 0644
set_perm "$MODPATH/state" 0 0 0700
for file in config.sh control.sh service.sh collector.sh uninstall.sh; do set_perm "$MODPATH/$file" 0 0 0755; done
set_perm "$MODPATH/zygisk/arm64-v8a.so" 0 0 0644
ui_print 'Single pb.encode Hook installed. Requires enabled Zygisk Next and a reboot.'
ui_print 'No LSPosed game scope. Fully exit/reopen game after enabling or selecting a target.'

#!/system/bin/sh
# This module replaces the earlier Zygisk candidate with the same module ID.
rm -f "$MODPATH/zygisk/arm64-v8a.so" "$MODPATH/lib/arm64-v8a/libminifire_core.so"
rm -f "$MODPATH/hunter_enabled" "$MODPATH/diagnostics.sh"
rmdir "$MODPATH/zygisk" "$MODPATH/lib/arm64-v8a" "$MODPATH/lib" 2>/dev/null || :
saved=0
INSTALLED=/data/adb/modules/minifire_compat_zygisk
old_code=$(sed -n 's/^versionCode=//p' "$INSTALLED/module.prop" 2>/dev/null || :)
case "$old_code" in ''|*[!0-9]*) old_code=0;; esac
if [ "$old_code" -ge 1000 ]; then
    previous=$(cat "$INSTALLED/game_enabled" 2>/dev/null || :)
    case "$previous" in 0|1) saved=$previous;; esac
    if [ "$INSTALLED" != "$MODPATH" ]; then
        mkdir -p "$MODPATH/state" && chmod 0700 "$MODPATH/state" || abort 'Cannot preserve private state'
        for file in ca.pem ca.key ca-filename; do
            if [ -f "$INSTALLED/state/$file" ]; then cp -p "$INSTALLED/state/$file" "$MODPATH/state/$file" || abort 'Cannot preserve local CA'; chmod 0600 "$MODPATH/state/$file"; fi
        done
    fi
fi
printf '%s\n' "$saved" > "$MODPATH/game_enabled" || abort 'Cannot initialize compatibility switch'
set_perm "$MODPATH/bin/minifire-external" 0 0 0755
set_perm "$MODPATH/game_enabled" 0 0 0644
for script in service.sh controller.sh control.sh route.sh trust.sh uninstall.sh; do set_perm "$MODPATH/$script" 0 0 0755; done
ui_print 'External proxy implementation installed. Reboot, then enable it from WebUI.'
ui_print 'The old Zygisk injection payload has been removed from this update.'

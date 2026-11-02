#!/system/bin/sh
# The installer sources this after extracting files into MODPATH.
# A ZIP update contains default flags. Copy valid flags from the active module
# before applying those defaults, so an upgrade does not silently turn it off.
INSTALLED_DIR=${MINIFIRE_INSTALLED_DIR:-/data/adb/modules/minifire_compat_zygisk}
for key in game_enabled hunter_enabled; do
    if [ "$INSTALLED_DIR" != "$MODPATH" ] && [ -f "$INSTALLED_DIR/$key" ]; then
        IFS= read -r previous < "$INSTALLED_DIR/$key"
        case "$previous" in
            0|1) printf '%s\n' "$previous" > "$MODPATH/$key" || abort "Cannot preserve $key";;
        esac
    fi
    if [ ! -f "$MODPATH/$key" ]; then
        printf '0\n' > "$MODPATH/$key" || abort "Cannot initialize $key"
    fi
    set_perm "$MODPATH/$key" 0 0 0644
done

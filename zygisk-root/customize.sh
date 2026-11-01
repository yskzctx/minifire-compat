#!/system/bin/sh
# The installer sources this after extracting files into MODPATH.
# Keep valid settings; initialize only files that are absent.
for key in game_enabled hunter_enabled; do
    if [ ! -f "$MODPATH/$key" ]; then
        printf '0\n' > "$MODPATH/$key" || abort "Cannot initialize $key"
    fi
    set_perm "$MODPATH/$key" 0 0 0644
done

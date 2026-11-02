#!/system/bin/sh
DEFAULT_GAME=com.miniworldroyale.sparkgame
valid_package(){
    [ "${#1}" -le 255 ] && printf '%s\n' "$1" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)+$'
}
read_target(){
    GAME=$DEFAULT_GAME
    if [ -f "$MODDIR/target_package" ]; then IFS= read -r GAME < "$MODDIR/target_package" || return 1; fi
    valid_package "$GAME"
}

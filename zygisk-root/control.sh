#!/system/bin/sh
MODDIR=${0%/*}
read_flag() {
    [ -f "$MODDIR/$1" ] || return 1
    IFS= read -r value < "$MODDIR/$1"
    case "$value" in 0|1) printf '%s' "$value";; *) return 1;; esac
}
case "$1" in
    status)
        game=$(read_flag game_enabled) || exit 1
        hunter=$(read_flag hunter_enabled) || exit 1
        printf 'game=%s\nhunter=%s\n' "$game" "$hunter"
        ;;
    game|hunter)
        case "$2" in 0|1) ;; *) exit 2;; esac
        key="${1}_enabled"
        [ -f "$MODDIR/$key" ] || exit 1
        tmp="$MODDIR/$key.tmp"
        printf '%s\n' "$2" > "$tmp" || exit 1
        chmod 0644 "$tmp" || exit 1
        mv -f "$tmp" "$MODDIR/$key" || exit 1
        read_flag "$key"
        printf '\n'
        ;;
    logs)
        logcat -d -b main -b system -b crash -v threadtime | tail -n 1500
        ;;
    *) exit 2;;
esac

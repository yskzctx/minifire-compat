#!/system/bin/sh
MODDIR=${0%/*}
STATE="$MODDIR/state"
IPTABLES=${MINIFIRE_IPTABLES:-iptables}
IP6TABLES=${MINIFIRE_IP6TABLES:-ip6tables}
ACTIVE=$IPTABLES
ipt() { "$ACTIVE" -w 5 -t nat "$@"; }
valid_uid() { case "$1" in ''|*[!0-9]*) return 1;; esac; [ "$1" -ge 10000 ] && [ "$1" -le 2147483647 ]; }
valid_ip() {
    case "$1" in ''|*[!0-9.]*) return 1;; esac
    saved_ifs=$IFS; IFS=.; set -- $1; IFS=$saved_ifs
    [ "$#" -eq 4 ] || return 1
    for octet in "$@"; do case "$octet" in ''|*[!0-9]*) return 1;; esac; [ "$octet" -le 255 ] || return 1; done
}
valid_port() { case "$1" in ''|*[!0-9]*) return 1;; esac; [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }
stop_route() {
    for ACTIVE in "$IPTABLES" "$IP6TABLES"; do
    if [ -f "$STATE/route_uid" ]; then
        IFS= read -r old_uid < "$STATE/route_uid"
        if valid_uid "$old_uid"; then
            count=0
            while [ "$count" -lt 16 ] && ipt -C OUTPUT -m owner --uid-owner "$old_uid" -j MFC_OUT 2>/dev/null; do
                ipt -D OUTPUT -m owner --uid-owner "$old_uid" -j MFC_OUT || break
                count=$((count+1))
            done
        fi
    fi
    ipt -F MFC_OUT 2>/dev/null || :
    ipt -F MFC_TCP 2>/dev/null || :
    ipt -X MFC_OUT 2>/dev/null || :
    ipt -X MFC_TCP 2>/dev/null || :
    done
    rm -f "$STATE/route_uid"
}
case "$1" in
    init)
        [ "$#" -eq 2 ] && valid_uid "$2" || exit 2
        stop_route
        mkdir -p "$STATE" && chmod 0700 "$STATE" || exit 1
        printf '%s\n' "$2" > "$STATE/route_uid" || exit 1
        for ACTIVE in "$IPTABLES" "$IP6TABLES"; do
        if ! {
            ipt -N MFC_TCP && ipt -N MFC_OUT &&
            ipt -A MFC_OUT -p tcp --dport 443 -j REDIRECT --to-ports 18443 &&
            ipt -A MFC_OUT -j MFC_TCP &&
            ipt -A OUTPUT -m owner --uid-owner "$2" -j MFC_OUT
        }; then stop_route; exit 1; fi
        done
        ;;
    lobby)
        [ "$#" -eq 2 ] && valid_port "$2" || exit 2
        for ACTIVE in "$IPTABLES" "$IP6TABLES"; do
            ipt -F MFC_TCP && ipt -A MFC_TCP -p tcp --dport "$2" -j REDIRECT --to-ports 18443 || exit 1
        done
        ;;
    lobby_clear)
        for ACTIVE in "$IPTABLES" "$IP6TABLES"; do ipt -F MFC_TCP || exit 1; done
        ;;
    stop) stop_route;;
    *) exit 2;;
esac

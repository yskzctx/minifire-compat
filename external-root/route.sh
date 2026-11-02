#!/system/bin/sh
MODDIR=${0%/*}
STATE="$MODDIR/state"
IPTABLES=${MINIFIRE_IPTABLES:-iptables}
IP6TABLES=${MINIFIRE_IP6TABLES:-ip6tables}
ACTIVE=$IPTABLES
TABLE=nat
mkdir -p "$STATE" && chmod 0700 "$STATE" || exit 1
ipt() { LC_ALL=C "$ACTIVE" -w 5 -t "$TABLE" "$@"; }
valid_uid() { case "$1" in ''|*[!0-9]*) return 1;; esac; [ "$1" -ge 10000 ] && [ "$1" -le 2147483647 ]; }
valid_ip() {
    case "$1" in ''|*[!0-9.]*) return 1;; esac
    saved_ifs=$IFS; IFS=.; set -- $1; IFS=$saved_ifs
    [ "$#" -eq 4 ] || return 1
    for octet in "$@"; do case "$octet" in ''|*[!0-9]*) return 1;; esac; [ "$octet" -le 255 ] || return 1; done
}
valid_port() { case "$1" in ''|*[!0-9]*) return 1;; esac; [ "$1" -ge 1 ] && [ "$1" -le 65535 ]; }
table_available(){
    if ipt -S OUTPUT >/dev/null 2> "$STATE/route-probe.txt"; then return 0; fi
    if grep -Eiq 'Table does not exist|table .*does not exist' "$STATE/route-probe.txt"; then return 2; fi
    cat "$STATE/route-probe.txt" >&2
    return 1
}
cleanup_table(){
    out_chain=$1; tcp_chain=$2
    probe_code=0; table_available || probe_code=$?
    [ "$probe_code" != 2 ] || return 0
    [ "$probe_code" = 0 ] || { printf 'route_inspection_failed\n'; return 1; }
    table_cleanup_failed=0
    if [ -f "$STATE/route_uid" ]; then
        IFS= read -r old_uid < "$STATE/route_uid"
        if valid_uid "$old_uid"; then
            count=0
            while [ "$count" -lt 16 ] && ipt -C OUTPUT -m owner --uid-owner "$old_uid" -j "$out_chain" 2>/dev/null; do
                ipt -D OUTPUT -m owner --uid-owner "$old_uid" -j "$out_chain" || { table_cleanup_failed=1; break; }
                count=$((count+1))
            done
            if ipt -C OUTPUT -m owner --uid-owner "$old_uid" -j "$out_chain" 2>/dev/null; then table_cleanup_failed=1; fi
        else
            table_cleanup_failed=1
        fi
    fi
    for own_chain in "$out_chain" "$tcp_chain"; do
        if ipt -S "$own_chain" >/dev/null 2>&1; then
            ipt -F "$own_chain" || table_cleanup_failed=1
        fi
    done
    for own_chain in "$out_chain" "$tcp_chain"; do
        if ipt -S "$own_chain" >/dev/null 2>&1; then
            ipt -X "$own_chain" || table_cleanup_failed=1
        fi
    done
    return "$table_cleanup_failed"
}
stop_route() {
    route_cleanup_failed=0
    TABLE=nat
    for ACTIVE in "$IPTABLES" "$IP6TABLES"; do
        cleanup_table MFC_OUT MFC_TCP || route_cleanup_failed=1
    done
    ACTIVE=$IP6TABLES; TABLE=filter
    cleanup_table MFC6_OUT MFC6_TCP || route_cleanup_failed=1
    [ "$route_cleanup_failed" = 0 ] || { printf 'route_cleanup_failed\n'; return 1; }
    rm -f "$STATE/route_uid" "$STATE/route_mode"
}
setup_nat(){
    ipt -N MFC_TCP && ipt -N MFC_OUT &&
    ipt -A MFC_OUT -d "$1" -j RETURN &&
    ipt -A MFC_OUT -p tcp --dport 443 -j REDIRECT --to-ports 18443 &&
    ipt -A MFC_OUT -j MFC_TCP &&
    ipt -A OUTPUT -m owner --uid-owner "$2" -j MFC_OUT
}
read_mode(){
    [ -f "$STATE/route_mode" ] || return 1
    IFS= read -r route_mode < "$STATE/route_mode"
    case "$route_mode" in dual_stack_nat|ipv4_with_ipv6_filter) return 0;; esac
    return 1
}
case "$1" in
    init)
        [ "$#" -eq 2 ] && valid_uid "$2" || exit 2
        stop_route || exit 1
        mkdir -p "$STATE" && chmod 0700 "$STATE" || exit 1
        printf '%s\n' "$2" > "$STATE/route_uid" || exit 1
        printf 'probing_route_tables\n' > "$STATE/route-capabilities.txt"
        ACTIVE=$IPTABLES; TABLE=nat
        if ! table_available || ! setup_nat 127.0.0.0/8 "$2"; then printf 'ipv4_nat_setup_failed\n' >&2; stop_route; exit 1; fi
        ACTIVE=$IP6TABLES; TABLE=nat
        probe_code=0; table_available || probe_code=$?
        if [ "$probe_code" = 0 ]; then
            if ! setup_nat ::1/128 "$2"; then stop_route; exit 1; fi
            printf 'dual_stack_nat\n' > "$STATE/route_mode"
        elif [ "$probe_code" = 2 ]; then
            printf 'ipv6_nat_absent\n' >> "$STATE/route-capabilities.txt"
            TABLE=filter
            if ! table_available || ! {
                ipt -N MFC6_TCP && ipt -N MFC6_OUT &&
                ipt -A MFC6_OUT -d ::1/128 -j RETURN &&
                ipt -A MFC6_OUT -p tcp --dport 443 -j REJECT --reject-with tcp-reset &&
                ipt -A MFC6_OUT -j MFC6_TCP &&
                ipt -I OUTPUT 1 -m owner --uid-owner "$2" -j MFC6_OUT
            }; then printf 'ipv6_filter_fallback_unavailable\n' >&2; stop_route; exit 1; fi
            printf 'ipv4_with_ipv6_filter\n' > "$STATE/route_mode"
        else stop_route; exit 1; fi
        cat "$STATE/route_mode" >> "$STATE/route-capabilities.txt"
        ;;
    lobby)
        [ "$#" -eq 2 ] && valid_port "$2" || exit 2
        read_mode || exit 1
        ACTIVE=$IPTABLES; TABLE=nat
        ipt -F MFC_TCP && ipt -A MFC_TCP -p tcp --dport "$2" -j REDIRECT --to-ports 18443 || exit 1
        ACTIVE=$IP6TABLES
        if [ "$route_mode" = dual_stack_nat ]; then
            ipt -F MFC_TCP && ipt -A MFC_TCP -p tcp --dport "$2" -j REDIRECT --to-ports 18443 || exit 1
        else
            TABLE=filter
            ipt -F MFC6_TCP && ipt -A MFC6_TCP -p tcp --dport "$2" -j REJECT --reject-with tcp-reset || exit 1
        fi
        ;;
    lobby_clear)
        read_mode || exit 1
        ACTIVE=$IPTABLES; TABLE=nat; ipt -F MFC_TCP || exit 1
        ACTIVE=$IP6TABLES
        if [ "$route_mode" = dual_stack_nat ]; then ipt -F MFC_TCP || exit 1
        else TABLE=filter; ipt -F MFC6_TCP || exit 1; fi
        ;;
    stop) stop_route;;
    *) exit 2;;
esac

#!/usr/bin/env bash
set -eu
fixture=$(mktemp -d)
case "$fixture" in */tmp.*) ;; *) exit 1;; esac
cleanup(){ rm -f "$fixture/route.sh" "$fixture/iptables" "$fixture/ip6tables" "$fixture/calls" "$fixture/state/route_uid" "$fixture/state/route_mode" "$fixture/state/route-probe.txt" "$fixture/state/route-capabilities.txt" "$fixture/mock"/*; rmdir "$fixture/state" "$fixture/mock" "$fixture" 2>/dev/null || :; }
trap cleanup EXIT
mkdir "$fixture/state" "$fixture/mock"
cp external-root/route.sh "$fixture/route.sh"
cat > "$fixture/iptables" <<'SH'
#!/bin/sh
family=4; case "$0" in *ip6tables) family=6;; esac
printf '%s %s\n' "$family" "$*" >> "$CALLS"
table=nat; previous=''; action=''; chain=''
for value in "$@"; do
 [ "$previous" != -t ] || table=$value
 case "$previous" in -A|-I|-D|-C|-N|-X|-F|-S) chain=$value;; esac
 case "$value" in -A|-I|-D|-C|-N|-X|-F|-S) action=$value;; esac
 previous=$value
done
if [ "$family:$table" = 6:nat ]; then
 if [ "${DENY_IPV6:-0}" = 1 ]; then printf 'Permission denied\n' >&2; exit 4; fi
 printf "ip6tables v1.8.11 (legacy): can't initialize ip6tables table nat: Table does not exist\n" >&2; exit 3
fi
if [ "${FAIL_REJECT:-0}" = 1 ]; then case " $* " in *' -j REJECT '*) printf 'REJECT unavailable\n' >&2; exit 2;; esac; fi
marker="$MOCK/$family.$table.$chain"
case "$action:$chain" in
 -S:OUTPUT) exit 0;;
 -C:OUTPUT) [ -f "$marker" ]; exit $?;;
 -A:OUTPUT|-I:OUTPUT) touch "$marker";;
 -D:OUTPUT) rm -f "$marker";;
 -N:*) touch "$marker";;
 -S:*) [ -f "$marker" ]; exit $?;;
 -X:*) rm -f "$marker";;
esac
SH
cp "$fixture/iptables" "$fixture/ip6tables"
chmod +x "$fixture/iptables" "$fixture/ip6tables"
export MINIFIRE_IPTABLES="$fixture/iptables" MINIFIRE_IP6TABLES="$fixture/ip6tables" CALLS="$fixture/calls" MOCK="$fixture/mock"
printf '10240\n' > "$fixture/state/route_uid"
sh "$fixture/route.sh" stop
[ ! -f "$fixture/state/route_uid" ]
sh "$fixture/route.sh" init 10240
[ "$(cat "$fixture/state/route_mode")" = ipv4_with_ipv6_filter ]
grep -q '^4 .*--dport 443 -j REDIRECT' "$CALLS"
grep -q '^6 .* -t filter .*--dport 443 -j REJECT --reject-with tcp-reset' "$CALLS"
grep -q '^6 .* -I OUTPUT 1 -m owner --uid-owner 10240 -j MFC6_OUT' "$CALLS"
sh "$fixture/route.sh" lobby 12345
grep -q '^6 .* -t filter .*--dport 12345 -j REJECT --reject-with tcp-reset' "$CALLS"
sh "$fixture/route.sh" lobby_clear
sh "$fixture/route.sh" stop
[ ! -f "$fixture/mock/4.nat.OUTPUT" ] && [ ! -f "$fixture/mock/6.filter.OUTPUT" ]
if grep -q -- '-F OUTPUT\|sysctl\|insmod' "$CALLS"; then exit 1; fi
echo 'missing IPv6 NAT uses UID-scoped IPv6 TCP rejection and fully removes its own rules'
printf '10240\n' > "$fixture/state/route_uid"
if DENY_IPV6=1 sh "$fixture/route.sh" stop; then echo 'real permission failure hidden' >&2; exit 1; fi
[ -f "$fixture/state/route_uid" ]
sh "$fixture/route.sh" stop
if FAIL_REJECT=1 sh "$fixture/route.sh" init 10240; then echo 'started without IPv6 enforcement' >&2; exit 1; fi
[ ! -f "$fixture/mock/4.nat.OUTPUT" ] && [ ! -f "$fixture/mock/6.filter.OUTPUT" ]
echo 'permission errors remain fatal and missing REJECT rolls back partial startup'

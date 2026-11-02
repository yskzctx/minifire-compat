#!/usr/bin/env bash
set -eu
fixture=$(mktemp -d)
case "$fixture" in */tmp.*) ;; *) exit 1;; esac
trap 'rm -f "$fixture/route.sh" "$fixture/iptables" "$fixture/calls" "$fixture/state/route_uid"; rmdir "$fixture/state" "$fixture" 2>/dev/null || :' EXIT
cp external-root/route.sh "$fixture/route.sh"
cat > "$fixture/iptables" <<'SH'
#!/bin/sh
printf '%s\n' "$*" >> "$CALLS"
case " $* " in *' -C '*) exit 1;; esac
SH
chmod +x "$fixture/iptables"
export MINIFIRE_IPTABLES="$fixture/iptables" MINIFIRE_IP6TABLES="$fixture/iptables" CALLS="$fixture/calls"
sh "$fixture/route.sh" init 10240
sh "$fixture/route.sh" lobby 12345
grep -q -- '-A OUTPUT -m owner --uid-owner 10240 -j MFC_OUT' "$CALLS"
grep -q -- '-A MFC_OUT -p tcp --dport 443 -j REDIRECT --to-ports 18443' "$CALLS"
grep -q -- '--dport 12345 -j REDIRECT --to-ports 18443' "$CALLS"
if grep -q -- '-F OUTPUT' "$CALLS"; then exit 1; fi
if sh "$fixture/route.sh" lobby '1234;bad'; then exit 1; fi
if sh "$fixture/route.sh" lobby 'bad'; then exit 1; fi
sh "$fixture/route.sh" stop
echo 'UID-scoped routing and invalid-input rejection ok'

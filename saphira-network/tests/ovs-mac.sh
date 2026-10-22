#!/bin/sh
# MAC identity handling for the OVS helpers (ovs-lib).
#
# The rule, proven on Hatchling: when a management address lives on a
# separate internal gateway port, the preserved hardware address
# belongs ON THAT PORT (runtime + unit file), never only on the
# bridge. Traffic sources from the port's MAC; the bridge MAC appears
# in almost no data traffic, so cloning there preserves nothing.
#
# Rootless: asserts pure validation logic and pre-flight ordering
# (invalid input must die before anything touches OVS). No bridge,
# no interface, no root required.

set -eu

here=$(cd -- "$(dirname -- "$0")" && pwd)
lib=$here/../files/ovs-lib

failures=0

ok()
{
	printf 'ok       %s\n' "$*"
}

bad()
{
	printf 'FAIL     %s\n' "$*" >&2
	failures=$((failures + 1))
}

# Extract valid_mac without executing the dispatch tail.
eval "$(sed -n '/^valid_mac()/,/^}/p' "$lib")"

for good in 52:54:00:db:ca:dd 4E:04:7F:6A:8D:77 02:93:f5:ba:6c:40; do
	if valid_mac "$good"; then
		ok "valid_mac accepts $good"
	else
		bad "valid_mac rejects $good"
	fi
done

for badmac in "" "00:00:00:00:00:00" "zz:zz:zz:zz:zz:zz" "52:54:00:db:ca" "52-54-00-db-ca-dd" "52:54:00:db:ca:dd:ee"; do
	if valid_mac "$badmac"; then
		bad "valid_mac accepts '$badmac'"
	else
		ok "valid_mac rejects '$badmac'"
	fi
done

# Invalid MAC must die in pre-flight, before OVS is even contacted.
# (ovs_running would die differently; the MAC error is the proof
# validation runs first.)
if "$lib" net add testbr0 testgw0 --mac "not-a-mac" 2>&1 | grep -q "invalid MAC"; then
	ok "net add rejects bad --mac before touching OVS"
else
	bad "net add accepted bad --mac"
fi

if [ "$failures" -eq 0 ]; then
	echo "ovs-mac: all assertions passed"
else
	echo "ovs-mac: $failures assertion(s) failed" >&2
	exit 1
fi

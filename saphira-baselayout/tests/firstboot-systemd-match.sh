#!/bin/bash
# The wizard's systemd unit must match the NIC by MAC address, never
# by interface name.
#
# Predictable names (enp2s0, enp1s0, ...) change with kernel
# enumeration and slot order, so a Name= match written during setup
# may never match on the next boot - and the fresh machine has no
# network to be fixed from (Minimer 2026-11-07: renamed NIC, no
# matching network). The MAC is stable across renames and is read
# from sysfs at apply time.
#
# The function under test is extracted mechanically from the shipped
# wizard at run time, so this can never drift from what the image
# actually runs: there is no second copy of the logic here.

set -uo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
wizard=${SAPHIRA_FIRSTBOOT:-$here/../files/saphira-firstboot}

failures=0
ok() { printf 'ok       %s\n' "$*"; }
bad() { printf 'FAIL     %s\n' "$*" >&2; failures=$((failures + 1)); }

test -r "$wizard" || { printf 'wizard not readable: %s\n' "$wizard" >&2; exit 1; }

extract_function() {
	awk -v want="$1" '
		$0 ~ "^" want "\\(\\)" { inside = 1 }
		inside { print }
		inside && /^}/ { exit }
	' "$wizard"
}

for fn in uses_systemd apply_interface_now; do
	extract_function "$fn" >/dev/null || bad "$fn not found in $wizard"
done

work=$(mktemp -d "${SAPHIRA_TMPDIR:-/build/tmp}/firstboot-mac-test.XXXXXX" 2>/dev/null || mktemp -d)
trap 'rm -rf -- "$work"' EXIT HUP INT TERM

# Fixture sysroot: one virtual NIC with a fixed MAC, one without an
# address file at all.
root=$work/root
sysfs=$work/sysfs
mkdir -p "$root/run/systemd/system" "$root/etc" \
	"$sysfs/eth9" "$sysfs/ethnob" "$sysfs/lo"
printf '1\n' > "$sysfs/eth9/type"
printf '02:00:5e:10:00:01\n' > "$sysfs/eth9/address"
mkdir -p "$sysfs/eth9/device"
printf '1\n' > "$sysfs/ethnob/type"
mkdir -p "$sysfs/ethnob/device"
printf '1\n' > "$sysfs/lo/type"

apply_for() {
	# $1=iface $2=v4mode $3=v6mode; writes the unit into the fixture.
	local iface=$1 v4=$2 v6=$3
	(
		root_dir=$root
		SYSFS_NET_DIR=$sysfs
		INTERFACE=$iface
		IPV4_MODE=$v4 IPV4_CIDR= IPV4_GATEWAY=
		IPV6_MODE=$v6 IPV6_CIDR= IPV6_GATEWAY=
		DNS_SERVERS= DNS_SEARCH=
		eval "$(extract_function uses_systemd)"
		eval "$(extract_function apply_interface_now)"
		apply_interface_now
	)
}

printf '%s\n' '# a NIC with a readable MAC matches by MAC, never by name'

apply_for eth9 dhcp dhcp
unit=$root/etc/systemd/network/10-firstboot-eth9.network
if test -f "$unit"; then
	ok 'the systemd unit is written under the interface name'
else
	bad 'the systemd unit was not written'
fi
if grep -qx 'MACAddress=02:00:5e:10:00:01' "$unit" 2>/dev/null; then
	ok 'the match pins the MAC address'
else
	bad "the match does not pin the MAC address: $(cat "$unit" 2>/dev/null | tr '\n' ';')"
fi
if grep -q '^Name=' "$unit" 2>/dev/null; then
	bad 'the match must not name the interface (names do not survive renames)'
else
	ok 'no Name= line: a rename cannot orphan the configuration'
fi
if grep -qx 'DHCP=yes' "$unit" 2>/dev/null; then
	ok 'the rest of the unit (DHCP=yes) is intact'
else
	bad 'the unit lost its network configuration'
fi

printf '%s\n' '# a NIC without a readable MAC keeps the name fallback'

apply_for ethnob dhcp off
unit=$root/etc/systemd/network/10-firstboot-ethnob.network
if grep -qx 'Name=ethnob' "$unit" 2>/dev/null; then
	ok 'unreadable MAC falls back to the interface name'
else
	bad "missing MAC must fall back to Name=, not to an empty match: $(cat "$unit" 2>/dev/null | tr '\n' ';')"
fi
if grep -q '^MACAddress=$' "$unit" 2>/dev/null; then
	bad 'an empty MACAddress= would match nothing'
else
	ok 'no empty MACAddress= line'
fi

if test "$failures" -ne 0; then
	printf 'firstboot-systemd-match: %s failure(s)\n' "$failures" >&2
	exit 1
fi
printf '%s\n' 'firstboot-systemd-match: OK'

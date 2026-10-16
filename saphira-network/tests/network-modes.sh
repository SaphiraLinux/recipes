#!/bin/sh
# Family isolation and resolver ownership for saphira-network.
#
# These are the properties firstboot's menus depend on, asserted
# against the shipped code itself (the config script's own
# introspection verbs), never against a copy of its logic:
#
#   - an explicit DHCPv6 selection never implicitly enables DHCPv4;
#   - an explicit DHCPv4 selection never implicitly enables IPv6
#     (neither SLAAC nor DHCPv6);
#   - SLAAC is kernel SLAAC and is never handed to dhcpcd;
#   - dhcpcd can never write the resolver, so the DNS choice recorded
#     by firstboot stays authoritative.
#
# Rootless: no live interface, no root, no dhcpcd run.

set -eu

here=$(cd -- "$(dirname -- "$0")" && pwd)
config=${SAPHIRA_NETWORK_CONFIG:-$here/../files/saphira-network-config}

test -x "$config" || {
	printf 'config script is not executable: %s\n' "$config" >&2
	exit 1
}

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

# plan V4MODE V6MODE -> the exact dhcpcd argument vector, or failure
# when no client would be started at all.
plan()
{
	"$config" dhcpcd-plan "$1" "$2" 2>/dev/null || printf '%s' none
}

# expect_plan LABEL V4MODE V6MODE EXPECTED
expect_plan()
{
	label=$1
	got=$(plan "$2" "$3")
	if test "$got" = "$4"; then
		ok "$label"
	else
		bad "$label: expected [$4], got [$got]"
	fi
}

printf '%s\n' '# address mode acceptance'

# SLAAC is IPv6-only; it must never be accepted for IPv4.
if "$config" mode-ok slaac 6 >/dev/null 2>&1; then
	ok 'slaac is a valid IPv6 mode'
else
	bad 'slaac must be a valid IPv6 mode'
fi
if "$config" mode-ok slaac 4 >/dev/null 2>&1; then
	bad 'slaac must NOT be a valid IPv4 mode'
else
	ok 'slaac is rejected for IPv4'
fi

printf '%s\n' '# required firstboot combinations'

# IPv6 Static  + IPv4 Static: no client at all.
expect_plan 'v6 static + v4 static -> no dhcpcd' static static none

# IPv6 SLAAC   + IPv4 Static: kernel SLAAC, never dhcpcd.
expect_plan 'v6 slaac + v4 static -> no dhcpcd (kernel SLAAC)' static slaac none

# IPv6 DHCPv6  + IPv4 Disabled: IPv6 client only.
expect_plan 'v6 dhcpv6 + v4 disabled -> -6 only' off dhcp '-6 -C resolv.conf'

# IPv6 Disabled + IPv4 DHCP: IPv4 client only.
expect_plan 'v6 disabled + v4 dhcp -> -4 only' dhcp off '-4 -C resolv.conf'

# IPv6 DHCPv6  + IPv4 DHCP: both families, and only because both were
# asked for.
expect_plan 'v6 dhcpv6 + v4 dhcp -> both families' dhcp dhcp '-C resolv.conf'

# IPv6 Disabled + IPv4 Disabled: the NIC is left untouched.
expect_plan 'v6 disabled + v4 disabled -> nothing runs' off off none

printf '%s\n' '# cross-family leakage'

# An IPv6-only DHCP selection (IPv4 off or static) must never produce
# the IPv4 flag.
for combo in 'off dhcp' 'static dhcp'; do
	set -- $combo
	got=$(plan "$1" "$2")
	case $got in
	*'-4'*) bad "IPv6-only DHCP leaked the IPv4 flag for v4=$1 v6=$2: [$got]" ;;
	*'-6'*) ok "v4=$1 v6=$2 is IPv6-only: [$got]" ;;
	*) bad "v4=$1 v6=$2 should start an IPv6 client, got [$got]" ;;
	esac
done

# An IPv4-only DHCP selection (IPv6 off, static or SLAAC) must never
# produce the IPv6 flag, and must never hand IPv6 to the client.
for combo in 'dhcp off' 'dhcp static' 'dhcp slaac'; do
	set -- $combo
	got=$(plan "$1" "$2")
	case $got in
	none) bad "v4=$1 v6=$2 should start the IPv4 client, got [none]" ;;
	*'-6'*) bad "v4=$1 v6=$2 leaked the IPv6 flag: [$got]" ;;
	*'-4'*) ok "v4=$1 v6=$2 is IPv4-only: [$got]" ;;
	*) bad "unexpected plan for v4=$1 v6=$2: [$got]" ;;
	esac
done

# Both families only when both were explicitly requested.
got=$(plan dhcp dhcp)
if test "$got" = '-C resolv.conf'; then
	ok 'v4 dhcp + v6 dhcp manages both, as chosen'
else
	bad "v4 dhcp + v6 dhcp must manage both, got [$got]"
fi

# SLAAC combined with IPv4 DHCP: the client must be IPv4-only and the
# kernel keeps IPv6.
got=$(plan dhcp slaac)
if test "$got" = '-4 -C resolv.conf'; then
	ok 'v6 slaac + v4 dhcp -> IPv4 client only, IPv6 stays with the kernel'
else
	bad "v6 slaac + v4 dhcp: expected [-4 -C resolv.conf], got [$got]"
fi

# SLAAC with IPv6 DHCPv6 is contradictory: the operator would be
# choosing both automatic mechanisms for one family. It is not offered
# by the wizard, and the schema must not silently pick one.
if "$config" dhcpcd-plan dhcp slaac >/dev/null 2>&1; then
	plan_slaac_dhcp=$(plan dhcp slaac)
	case $plan_slaac_dhcp in
	*'-6'*) bad 'v6 slaac + v4 dhcp must not hand IPv6 to dhcpcd' ;;
	*) ok 'v6 slaac + v4 dhcp never hands IPv6 to dhcpcd' ;;
	esac
fi

printf '%s\n' '# resolver ownership'

# Whatever combination produces a client invocation, the resolver hook
# must always be disabled: firstboot's DNS choice is authoritative.
for v4 in off static dhcp; do
	for v6 in off static slaac dhcp; do
		got=$(plan "$v4" "$v6")
		case $got in
		none) continue ;;
		esac
		case $got in
		*'-C resolv.conf'*) ;;
		*) bad "resolver hook not disabled for v4=$v4 v6=$v6: [$got]" ;;
		esac
	done
done
ok 'every client invocation disables the dhcpcd resolver hook'

printf '%s\n' '# no client for automatic or disabled families'

# SLAAC, static and off must never reach dhcpcd in any combination with
# IPv4 off, because IPv4 off means the operator did not ask for a
# client.
for v6 in off static slaac; do
	if test "$(plan off "$v6")" = none; then
		ok "v4 disabled + v6 $v6 starts nothing"
	else
		bad "v4 disabled + v6 $v6 must start nothing"
	fi
done

if test "$failures" -ne 0; then
	printf 'network-modes: %d failure(s)\n' "$failures" >&2
	exit 1
fi
printf '%s\n' 'network-modes: OK'
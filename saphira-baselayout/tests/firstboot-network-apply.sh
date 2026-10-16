#!/bin/bash
# The wizard's apply path, end to end, against the tool that actually
# runs at boot.
#
# The mode the wizard offers the operator must be expressible by the
# binary the boot service executes. It was not: firstboot applied through
# a second, older copy of saphira-network-config that had no notion of
# SLAAC at all, so choosing it failed the apply outright - and a failed
# apply armed the first-boot marker again, so the machine came back to
# setup on the next boot and lost the network it had just been given.
#
# So this drives the shipped helper (which writes the configuration) and
# then hands what it wrote to the shipped owning tool for validation.
# Nothing here re-implements either side: if the helper and the tool ever
# drift apart again, this fails rather than the operator's first boot.

set -uo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
helper=${SAPHIRA_APPLY_NETWORK:-$here/../files/libexec/apply-network.sh}
owner=${SAPHIRA_NETWORK_CONFIG:-$here/../../saphira-network/files/saphira-network-config}

failures=0
ok() { printf 'ok       %s\n' "$*"; }
bad() { printf 'FAIL     %s\n' "$*" >&2; failures=$((failures + 1)); }

for f in "$helper" "$owner"; do
	test -r "$f" || { printf 'not readable: %s\n' "$f" >&2; exit 1; }
done

# The helper requires uid 0; a private user namespace provides it without
# acquiring anything.
if test "$(id -u)" -ne 0 && test "${FIRSTBOOT_APPLY_NS:-0}" != 1; then
	if command -v unshare >/dev/null 2>&1; then
		exec env FIRSTBOOT_APPLY_NS=1 unshare -rm "$0" "$@"
	fi
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

root=$work/root
state=$root/var/lib/saphira-firstboot
install -d -m 0755 "$root/etc" "$state"
chmod 0700 "$state"
printf 'active\n' > "$state/active"
chmod 0600 "$state/active"

write_state()
{
	# Split declarations: `local a=$1 b=$a` declares every name unset
	# before assigning, so the second expansion trips `set -u`.
	local name=$1
	local file=$state/$name.conf
	{
		printf 'TYPE=physical\n'
		printf 'INTERFACE=%s\n' "${2:-eth0}"
		printf 'IPV4_MODE=%s\n' "$3"
		printf 'IPV4_CIDR=%s\n' "$4"
		printf 'IPV4_GATEWAY=\nIPV4_METRIC=\n'
		printf 'IPV6_MODE=%s\n' "$5"
		printf 'IPV6_CIDR=%s\n' "$6"
		printf 'IPV6_GATEWAY=\nIPV6_METRIC=\n'
		printf 'DNS_SERVERS=9.9.9.9\n'
		printf 'DNS_SEARCH=\n'
	} > "$file"
	chmod 0600 "$file"
	printf '%s\n' "$file"
}

# Run the shipped helper's apply, with activation off: this asserts the
# writing half. Activation would touch live interfaces, which is not what
# this suite is for and would make it unsafe to run anywhere.
apply_via_helper()
{
	env SAPHIRA_NETWORK_ROOT=$root \
	    SAPHIRA_FIRSTBOOT_STATE_DIR=$state \
	    SAPHIRA_NETWORK_APPLY=0 \
	    SAPHIRA_NETWORK_SKIP_OWNERSHIP=1 \
		"$helper" apply "$1" 2>&1
}

# Hand the written directory to the tool the boot service runs.
validate_via_owner()
{
	env SAPHIRA_NETWORK_DIR=$root/etc/saphira-network.d \
	    SAPHIRA_NETWORK_STATE_DIR=$work/state \
	    SAPHIRA_RESOLV_CONF=$work/resolv.conf \
	    AKADATA_NETWORK_WORK_DIR=$work \
		"$owner" validate 2>&1
}

# label iface v4mode v4cidr v6mode v6cidr expect(helper) expect(owner)
scenario()
{
	local label=$1 iface=$2 v4=$3 v4cidr=$4 v6=$5 v6cidr=$6
	shift 6
	local helper_wants=$1 owner_wants=$2

	rm -rf "$root/etc/saphira-network.d"
	local state_file
	state_file=$(write_state "$iface-$v4-$v6" "$iface" "$v4" "$v4cidr" "$v6" "$v6cidr")

	local out status
	out=$(apply_via_helper "$state_file")
	status=$?
	if test "$helper_wants" = accept; then
		if test "$status" -ne 0; then
			bad "$label: the helper rejected it: $out"
			return
		fi
		ok "$label: the wizard helper accepts it"
	else
		if test "$status" -eq 0; then
			bad "$label: the helper should have rejected it"
			return
		fi
		ok "$label: the wizard helper rejects it"
		return
	fi

	out=$(validate_via_owner)
	status=$?
	if test "$owner_wants" = accept; then
		if test "$status" -ne 0; then
			bad "$label: the tool that runs at boot rejected what the wizard wrote: $out"
			return
		fi
		ok "$label: the tool that runs at boot accepts what the wizard wrote"
	else
		if test "$status" -eq 0; then
			bad "$label: the boot tool should have rejected it"
			return
		fi
		ok "$label: the boot tool rejects it"
	fi
}

printf '%s\n' '# modes the wizard offers, written by the helper and read by the owner'

# SLAAC is the case that broke: an IPv6 kernel mode the old copy could
# not represent at all.
scenario 'SLAAC'        eth0 dhcp '' slaac ''      accept accept
# The other selections the wizard offers.
scenario 'DHCPv6'       eth0 dhcp '' dhcp  ''      accept accept
scenario 'static IPv4'  eth0 static 192.0.2.10/24 off '' accept accept
scenario 'both static'  eth0 static 192.0.2.10/24 static 2001:db8::10/64 accept accept
scenario 'IPv4 only'    eth0 static 192.0.2.10/24 off '' accept accept
scenario 'IPv6 only'    eth0 off ''       slaac ''      accept accept

printf '%s\n' '# SLAAC is IPv6-only, and that is still enforced'

# SLAAC is an IPv6-only mode, so a configuration that asks for it on IPv4
# is meaningless and must be refused rather than reinterpreted as a DHCP
# client. The helper refuses it, so the wizard can never write it; the
# owning tool's own refusal of the same thing is asserted directly below,
# because it is reachable by anything else that writes a config file.
scenario 'SLAAC as the IPv4 mode' eth0 slaac '' off '' reject reject

printf '%s\n' '# the written configuration lands where the boot service reads'

rm -rf "$root/etc/saphira-network.d"
state_file=$(write_state 'placement' eth0 dhcp '' slaac '')
apply_via_helper "$state_file" >/dev/null
if test -f "$root/etc/saphira-network.d/eth0.conf"; then
	ok 'the helper writes into /etc/saphira-network.d, the directory the owner reads'
else
	bad "the helper did not write /etc/saphira-network.d/eth0.conf; found: $(ls -A "$root/etc" 2>/dev/null | tr '\n' ' ')"
fi
if grep -q '^IPV6_MODE=slaac$' "$root/etc/saphira-network.d/eth0.conf" 2>/dev/null; then
	ok 'the written configuration preserves the selected mode'
else
	bad 'the written configuration lost the selected IPv6 mode'
fi
if test ! -e "$root/etc/network.d/eth0.conf"; then
	ok 'nothing is written to the legacy /etc/network.d'
else
	bad 'the helper must not write to the legacy directory'
fi

printf '%s\n' '# the owning tool rejects SLAAC for IPv4 on its own too'

if "$owner" mode-ok slaac 6 >/dev/null 2>&1; then
	ok 'the owning tool accepts SLAAC for IPv6'
else
	bad 'the owning tool must accept SLAAC for IPv6'
fi
if "$owner" mode-ok slaac 4 >/dev/null 2>&1; then
	bad 'the owning tool must reject SLAAC for IPv4'
else
	ok 'the owning tool rejects SLAAC for IPv4'
fi

if test "$failures" -ne 0; then
	printf 'firstboot-network-apply: %d failure(s)\n' "$failures" >&2
	exit 1
fi
printf '%s\n' 'firstboot-network-apply: OK'
#!/bin/bash
# saphira-network-config must have exactly ONE owner, ONE path, and ONE
# configuration directory.
#
# How this defect came to exist: saphira-baselayout shipped its own older
# copy of saphira-network-config at /sbin, saphira-network shipped the
# real one at /usr/sbin, and the firstboot wizard applied through the
# /sbin copy while the boot service ran the /usr/sbin one. The two
# disagreed about everything that matters - the /sbin copy read
# /etc/network.conf and /etc/network.d, the /usr/sbin copy reads
# /etc/saphira-network.conf and /etc/saphira-network.d - and the /sbin
# copy did not even understand SLAAC, a mode the wizard offers the
# operator. So a reasonable answer either failed the apply (leaving the
# first-boot marker armed, so setup was offered again on every reboot)
# or was written where the boot service only reaches it by fallback
# (network lost on reboot).
#
# Nothing caught it because only one of the two copies had a test:
# network-modes.sh exercises the /usr/sbin copy. These checks exist so a
# second copy can never be added quietly again.

set -uo pipefail

here=$(cd -- "$(dirname -- "$0")" && pwd)
root=$(cd -- "$here/../.." && pwd)

failures=0
ok() { printf 'ok       %s\n' "$*"; }
bad() { printf 'FAIL     %s\n' "$*" >&2; failures=$((failures + 1)); }

printf '%s\n' '# saphira-network-config is installed exactly once'

# Every recipe that installs the tool, and where it puts it.
owners=$(
	/usr/bin/grep -rn 'sbin/saphira-network-config' \
		--include='recipe.sh' "$root" 2>/dev/null |
		/usr/bin/grep -v '/tests/'
)
count=$(printf '%s' "$owners" | /usr/bin/grep -c . || true)
if test "${count:-0}" -eq 1; then
	owner_recipe=${owners%%:*}
	ok "one recipe installs the tool ($(basename "$(dirname "$owner_recipe")"))"
else
	bad "saphira-network-config must be installed by exactly one recipe, found ${count:-0}:"
	printf '%s\n' "$owners" >&2
fi

# No second copy may exist in any recipe tree, at any path.
copies=$(/usr/bin/find "$root" -name 'saphira-network-config' -type f \
	-not -path '*/tests/*' -not -path '*/.git/*' 2>/dev/null)
copy_count=$(printf '%s\n' "$copies" | /usr/bin/grep -c . || true)
if test "${copy_count:-0}" -eq 1; then
	ok 'exactly one saphira-network-config source file exists'
else
	bad "found ${copy_count:-0} copies of the tool; there must be exactly one:"
	printf '%s\n' "$copies" >&2
fi

# The payload path is the owning package's, and the legacy /sbin slot is
# gone: two paths is what made the split invisible in the first place.
if printf '%s' "$owners" | /usr/bin/grep -q '/usr/sbin/saphira-network-config'; then
	ok 'the tool is installed at /usr/sbin, where both units run it'
else
	bad 'the tool must be installed at /usr/sbin/saphira-network-config'
fi
if printf '%s' "$owners" | /usr/bin/grep -q '\$PKGDEST/sbin/saphira-network-config'; then
	bad 'a /sbin copy is being installed again; that split caused this defect'
else
	ok 'no /sbin copy is installed'
fi

printf '%s\n' '# the wizard applies through the same tool the boot service runs'

helper=$root/saphira-baselayout/files/libexec/apply-network.sh
test -r "$helper" || { printf 'helper not readable: %s\n' "$helper" >&2; exit 1; }

# Read the default out of VAR=${OTHER:-default}, and the directory out of
# a path, with plain sed rather than a hand-rolled parser.
default_of()
{
	/usr/bin/grep -m1 "^$1=" "$2" | /usr/bin/sed 's|^[^:]*:-||; s|}$||'
}
dir_after_etc()
{
	/usr/bin/grep -m1 "^$1=" "$2" | /usr/bin/sed 's|^.*/etc/||; s|}$||'
}
helper_service=$(default_of NETWORK_SERVICE "$helper")
initd_command=$(/usr/bin/sed -n 's/^command="\(.*\)"$/\1/p' \
	"$root/saphira-network/files/saphira-network.initd" | /usr/bin/head -1)
unit_exec=$(/usr/bin/sed -n 's|^ExecStart=\(.*\) start$|\1|p' \
	"$root/saphira-network/files/saphira-network.service" | /usr/bin/head -1)

if test "$helper_service" = "$initd_command"; then
	ok "the wizard and the OpenRC unit run the same binary ($initd_command)"
else
	bad "the wizard applies through '$helper_service' but the OpenRC unit runs '$initd_command'"
fi
if test "$helper_service" = "$unit_exec"; then
	ok "the wizard and the systemd unit run the same binary ($unit_exec)"
else
	bad "the wizard applies through '$helper_service' but the systemd unit runs '$unit_exec'"
fi

printf '%s\n' '# the wizard writes where the boot service reads'

dir_of()
{
	dir_after_etc "$1" "$2"
}
helper_dir=$(dir_of NETWORK_DIR "$helper")
owner_dir=$(dir_after_etc CONFIG_DIR "$root/saphira-network/files/saphira-network-config")

if test "$helper_dir" = "$owner_dir"; then
	ok "the wizard writes /etc/$helper_dir, the directory the owner reads"
else
	bad "the wizard writes /etc/$helper_dir but the owning tool reads /etc/$owner_dir"
fi
if test "$helper_dir" = network.d; then
	bad 'the wizard must not write /etc/network.d: the owner only reads it as a legacy fallback'
else
	ok 'the wizard no longer relies on the legacy compatibility directory'
fi

printf '%s\n' '# the loopback seed is where the owner reads it'

# The seed must not sit only in the legacy directory: once the wizard
# writes a real interface file into the owner's directory, the owner stops
# consulting the fallback entirely - and loopback is not optional.
for apply in "$root/saphira-baselayout/files/libexec/apply-accounts.sh"; do
	if /usr/bin/grep -q 'saphira-network.d/00-loopback.conf' "$apply"; then
		ok 'the loopback seed is installed into the owner directory'
	else
		bad "the loopback seed must be installed into saphira-network.d: $apply"
	fi
done

printf '%s\n' '# the owning tool can express every mode the wizard offers'

owner=$root/saphira-network/files/saphira-network-config
for mode in slaac dhcp static off; do
	if /usr/bin/grep -q "$mode" "$owner"; then
		ok "the owning tool understands $mode"
	else
		bad "the owning tool does not understand $mode, which the wizard offers"
	fi
done

# No consumer may reference the retired /sbin slot: openrc's network
# init.d shipped command=/sbin/saphira-network-config long after the
# tool moved to /usr/sbin, and the gate above (install sites only)
# never saw references. This bricks OpenRC networking at boot.
stray_refs=$(/usr/bin/grep -rn --include='*' -E '(^|[^/])sbin/saphira-network-config' \
	"$root" 2>/dev/null | /usr/bin/grep -v '/tests/' | /usr/bin/grep -v '\.md:' || true)
if test -z "$stray_refs"; then
	ok 'no references to the retired /sbin slot outside tests'
else
	bad 'references to retired /sbin/saphira-network-config (use /usr/sbin):'
	printf '%s\n' "$stray_refs" >&2
fi

if test "$failures" -ne 0; then
	printf 'network-config-ownership: %d failure(s)\n' "$failures" >&2
	exit 1
fi
printf '%s\n' 'network-config-ownership: OK'
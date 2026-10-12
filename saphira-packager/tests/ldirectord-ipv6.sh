#!/bin/sh

# ldirectord IPv6 parsing consistency: static assertions that every IPv6
# address character class in the vendored source agrees, and that the
# shipped example configuration is IPv6-first. No build required.
#
# Policy encoded: Saphira Linux is IPv6-first, so a shipped IPv6 code path
# that is subtly wrong is worse than one that is absent. This gate exists
# because the file was internally inconsistent for the whole of its
# packaged life: the configuration parsers accepted `[0-9A-Fa-f:.]' while
# eleven other sites used the dotless `[0-9A-Fa-f:]', which cannot match an
# IPv4-mapped literal such as [::ffff:192.0.2.11]:80.
#
# Two proven failure modes that a dotless class causes, both reproduced
# against the daemon's own regexes (see the patch header for the output):
#
#   ld_read_ipvsadm              a mapped real server is parsed out of
#                                 ldirectord.cf but not back out of
#                                 `ipvsadm -Ln', so it is re-added on
#                                 every sync interval forever, with only
#                                 a debug-level-2 message.
#   _ld_read_config_virtual_...   the fallthrough is `split /:/', so a
#                                 mapped VIRTUAL address is mangled to
#                                 server="[" with an empty port, and
#                                 ldirectord programs a garbage IPVS
#                                 virtual service.
#
# The check is deliberately a consistency check on the character class,
# not a test of ldirectord's behaviour: it needs no Perl, no configure
# run, and no built package, so it can gate every commit.
#
# usage: ldirectord-ipv6.sh (operates on the source tree it lives in)

set -eu

source_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
pkg=$source_root/resource-agents
tarball=$pkg/files/v4.18.0.tar.gz

fail()
{
	printf '%s\n' "ldirectord-ipv6: $*" >&2
	exit 1
}

[ -f "$tarball" ] || fail "vendored source is missing: $tarball"

work=$(mktemp -d "${SAPHIRA_TMPDIR:-/build/tmp}/ldirectord-ipv6.XXXXXX")
trap 'rm -rf -- "$work"' EXIT HUP INT TERM

# Apply the package's own patches in order, exactly as the build does, so
# the assertion runs against the code that will actually ship.
tar -xzf "$tarball" -C "$work"
src=$work/resource-agents-4.18.0
[ -d "$src" ] || fail "unexpected tarball layout"
for p in "$pkg"/files/000*.patch; do
	[ -f "$p" ] || continue
	if ! (cd "$src" && patch -Np1 -p1 -i "$p" >/dev/null 2>&1); then
		fail "patch does not apply cleanly: ${p##*/}"
	fi
done
script=$src/ldirectord/ldirectord.in
[ -f "$script" ] || fail "ldirectord.in not found in the patched tree"

# --- 1. every IPv6 address class must include the dot ------------------
#
# A bracketed IPv6 literal may legally contain a dot only in the
# IPv4-mapped/compatible forms (::ffff:192.0.2.1), so a class without a
# dot is strictly narrower than one with it, and the narrower form is
# always the bug.

dotless=$(grep -c '0-9A-Fa-f:\]\+' "$script" || true)
if [ "$dotless" -ne 0 ]; then
	printf '%s\n' "ldirectord-ipv6: $dotless IPv6 character class(es) omit the dot and cannot match an IPv4-mapped literal:" >&2
	grep -n '0-9A-Fa-f:\]\+' "$script" >&2
	printf '%s\n' "ldirectord-ipv6: see files/0004-ldirectord-accept-IPv4-mapped-IPv6-literals.patch" >&2
	exit 1
fi

dotted=$(grep -c '0-9A-Fa-f:\.\]\+' "$script" || true)
[ "$dotted" -gt 0 ] || fail "no IPv6 character class with a dot found; the grep above is not matching what it should"

# --- 2. the class must be uniform, not merely present -----------------
#
# A future patch that reintroduces a second spelling must fail here, so
# compare the set of distinct classes rather than just counting matches.

classes=$(grep -o '0-9A-Fa-f:\.\]\*\|0-9A-Fa-f:\.\]\+\|0-9A-Fa-f:\]\*\|0-9A-Fa-f:\]\+' "$script" |
	sort -u | tr '\n' ' ')
n=$(printf '%s' "$classes" | wc -w)
if [ "$n" -ne 1 ]; then
	printf '%s\n' "ldirectord-ipv6: IPv6 address classes are not uniform: $classes" >&2
	printf '%s\n' "ldirectord-ipv6: every site must use the same spelling so a mapped literal parses everywhere" >&2
	exit 1
fi

# --- 3. the example configuration must be IPv6-first ------------------
#
# Saphira promotes IPv6 as the way forward. An example whose only virtual
# service is IPv4 teaches the wrong default even though the daemon handles
# v6 correctly.

example=$pkg/files/ldirectord.cf.example
[ -f "$example" ] || fail "missing example configuration: $example"

grep -Eq '^[[:space:]]*virtual6=' "$example" ||
	fail "example config has no virtual6 service; an IPv6-first distro must not ship an IPv4-only example"
grep -Eq '^[[:space:]]*real6=' "$example" ||
	fail "example config has no real6 server; a virtual6 with no real6 cannot forward anything"

# The bracketed-port requirement is the single most common IPv6 mistake
# and the one the parser is strictest about, so the example has to
# demonstrate it rather than contradict it.
if grep -Eq '^[[:space:]]*(virtual6|real6)=\[[^]]+\]:' "$example"; then
	:
else
	fail "example config never shows the bracketed IPv6-with-port form; document the syntax operators get wrong"
fi

# An unbracketed v6 address carrying a port is the specific mistake the
# parser rejects. It must not appear as an active (uncommented) line.
if grep -Eq '^[[:space:]]*(virtual6|real6)=[0-9A-Fa-f]*:[0-9A-Fa-f:]*:[0-9]+([[:space:]]|$)' "$example"; then
	fail "example config contains an unbracketed IPv6 address with a port; the port is read as part of the address"
fi

# --- 4. the service definitions must not exclude IPv6 ----------------

for f in "$pkg"/files/ldirectord.service "$pkg"/files/ldirectord.initd; do
	[ -f "$f" ] || continue
	# RestrictAddressFamilies without AF_INET6 would silently break every
	# v6 virtual service at runtime rather than failing to start.
	if grep -q 'RestrictAddressFamilies' "$f"; then
		grep -q 'AF_INET6' "$f" ||
			fail "${f##*/}: RestrictAddressFamilies omits AF_INET6, which would break every IPv6 virtual service"
	fi
	# A firewall-mark virtual service is addressed by netfilter, so the
	# director needs AF_NETLINK; an IPv4-only allowlist would not do.
	if grep -q 'RestrictAddressFamilies' "$f"; then
		grep -qE 'AF_NETLINK|AF_UNSPEC' "$f" ||
			fail "${f##*/}: RestrictAddressFamilies omits AF_NETLINK, which ldirectord needs to program the IPVS table and to manage fwm services"
	fi
done

printf '%s\n' "ldirectord-ipv6: OK ($dotted uniform IPv6 address class(es); example config is IPv6-first; service definitions permit AF_INET6)"

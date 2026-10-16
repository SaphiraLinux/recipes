#!/bin/sh
# ensure-identity must not paste a "/" root onto a path.
#
# The reconciler joins its root onto every path as "$ROOT$path". With the
# normal root of "/" that produced "//etc/passwd", "//var/lib/dhcpcd",
# and so on. A path beginning with exactly two slashes is
# implementation-defined, and chown(1) rejects it with EINVAL. The
# symptom was extremely confusing: the account was created, the log said
# so, and then reconciliation died on the account's OWN home directory -
#
#   ensure-identity: user dhcpcd (157:157) created
#   chown: changing ownership of '//var/lib/dhcpcd': Invalid argument
#   ensure-identity: ERROR: cannot set ownership on /var/lib/dhcpcd
#
# - so the package refused to install with an error naming a path the
# caller never wrote. Found while declaring the dhcpcd identity, the
# first fragment in the tree to carry a home through the real image
# build path.
#
# Both roots are exercised, because fixing one can easily break the
# other: the alternate root must behave exactly as it always did, and the
# "/" root must stop producing a double slash. The "/" case runs in a
# private user namespace where uid 0 is mapped, so chown is real rather
# than refused - which is what makes the EINVAL observable instead of
# merely asserted. It creates one uniquely named directory under /var/lib
# and removes it again.

set -u

here=$(cd -- "$(dirname -- "$0")" && pwd)
helper=${SAPHIRA_ENSURE_IDENTITY:-$here/../../saphira-baselayout/files/libexec/ensure-identity.sh}

test -r "$helper" || {
	printf 'ensure-identity.sh is not readable: %s\n' "$helper" >&2
	exit 1
}

failures=0
ok() { printf 'ok       %s\n' "$*"; }
bad() { printf 'FAIL     %s\n' "$*" >&2; failures=$((failures + 1)); }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

seed_root()
{
	local root=$1
	mkdir -p "$root/etc"
	printf 'root:x:0:0:root:/root:/bin/bash\n' > "$root/etc/passwd"
	printf 'root:x:0:\n' > "$root/etc/group"
	printf 'root:!:1:0:99999:7:::\n' > "$root/etc/shadow"
	chmod 0644 "$root/etc/passwd" "$root/etc/group"
	chmod 0600 "$root/etc/shadow"
}

write_fragment()
{
	local path=$1
	mkdir -p "${path%/*}"
	{
		printf '# root-join probe\n'
		printf 'dir %s 0755 root root\n' "$2"
	} > "$path"
}

# The "/" case has to happen first and under uid 0, because that is what
# makes chown's EINVAL observable. Everything else runs afterwards, in
# that namespace, so the alternate-root case is exercised in the same
# interpreter that proved the defect is gone.
if test "$(id -u)" -ne 0 && test "${JOIN_NS:-0}" != 1 &&
	command -v unshare >/dev/null 2>&1; then
	exec env JOIN_NS=1 unshare -rm "$0" "$@"
fi

printf '%s\n' '# a "/" root does not produce a double slash'

# A "/" root has to be a real "/" (that is the whole point: the join is
# what is under test) but must not be the controller's. Bind a scratch
# tree over /etc and /var/lib inside this private mount namespace, so
# "/" holds our own account database and our own probe directory. That
# also keeps the run from touching anything real.
slash=$work/slash
seed_root "$slash"
mkdir -p "$slash/var/lib"
if ! mount --bind "$slash/etc" /etc 2>/dev/null ||
	! mount --bind "$slash/var/lib" /var/lib 2>/dev/null; then
	bad 'cannot bind a scratch tree over /etc and /var/lib'
	printf 'ensure-identity-root-join: %d failure(s)\n' "$((failures + 1))" >&2
	exit 1
fi

write_fragment "$work/slash.d/slash" /var/lib/rootjoin-probe
out=$(SAPHIRA_ENSURE_ROOT=/ sh "$helper" "$work/slash.d/slash" 2>&1)
status=$?
if test "$status" -eq 0; then
	ok 'a "/" root reconciles successfully (no EINVAL from chown)'
else
	bad "a \"/\" root must reconcile: $out"
fi
if test -d "/var/lib/rootjoin-probe"; then
	ok 'the declared directory is created'
else
	bad "the directory was not created: $out"
fi
case $out in
*'//'*)
	bad "a double-slashed path was used: $out"
	;;
*)
	ok 'no double-slashed path is used with a "/" root'
	;;
esac
if printf '%s\n' "$out" | grep -q 'Invalid argument'; then
	bad 'chown reported Invalid argument, the double-slash defect'
else
	ok 'chown did not report Invalid argument'
fi

printf '%s\n' '# an alternate root behaves exactly as before'

alt=$work/alt
seed_root "$alt"
# Root-relative here: this root IS the filesystem, so "/var/lib/x" means
# "$alt/var/lib/x". Declaring a host-absolute path instead would test a
# different join entirely.
write_fragment "$work/alt.d/alt" /var/lib/jointest
out=$(SAPHIRA_ENSURE_ROOT=$alt sh "$helper" "$work/alt.d/alt" 2>&1)
status=$?
if test "$status" -eq 0; then
	ok 'an alternate root reconciles successfully'
else
	bad "an alternate root must still succeed: $out"
fi
if test -d "$alt/var/lib/jointest"; then
	ok 'the declared directory is created under the alternate root'
else
	bad "the directory was not created under $alt: $out"
fi
case $out in
*'//'*)
	bad "a double slash appeared in an alternate-root run: $out"
	;;
*)
	ok 'no double-slashed path in an alternate-root run'
	;;
esac

printf '%s\n' '# the account database is still found under a "/" root'

# The normalisation must not lose the account files: "$ROOT/etc/passwd"
# has to resolve to "/etc/passwd", not "etc/passwd".
write_fragment "$work/acct.d/acct" /var/lib/rootjoin-probe2
out=$(SAPHIRA_ENSURE_ROOT=/ sh "$helper" "$work/acct.d/acct" 2>&1)
if printf '%s\n' "$out" | grep -q 'account database is missing'; then
	bad "a \"/\" root can no longer find the account database: $out"
else
	ok 'the account database is found with a "/" root'
fi

printf '%s\n' '# the normalising assignment is present'

if grep -Eq '^/\) ROOT= ;;$' "$helper"; then
	ok 'a "/" root is normalised to empty before any path is built'
else
	bad 'the "/" root normalisation is missing from the helper'
fi

if test "$failures" -ne 0; then
	printf 'ensure-identity-root-join: %d failure(s)\n' "$failures" >&2
	exit 1
fi
printf '%s\n' 'ensure-identity-root-join: OK'
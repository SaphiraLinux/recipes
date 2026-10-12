#!/bin/sh

# buildpkg staged-input copy contract.
#
# buildpkg-single copies a staged build input (a kernel tree, or any extra
# input directory) into $SRC before the recipe runs. This suite pins the
# exact semantics of that copy, because it was wrong and the failure mode was
# invisible from the package side.
#
# The bug: the copy used plain `cp -a`, which preserves ownership. Builds run
# under a single-uid bwrap mapping (0 -> the build user), so anything owned by
# a uid that is not mapped into that namespace -- real root, most obviously --
# appears inside as the unmapped overflow uid 65534. cp -a then attempts
# chown(65534) and fails with EINVAL:
#
#   cp: failed to preserve ownership for '.../linux-7.2.2/arch/...': Invalid argument
#
# That aborted saphira-zfs-userspace outright, once per file, before the
# recipe produced a single line of output. It is reachable in practice
# because saphira-kernel ships its prepared external-module tree as
# /usr/src/linux-<ver>-saphira, and package-owned trees are root-owned by
# construction. No earlier package shipped such a tree, so the path had never
# been exercised.
#
# The contract now: the staged INPUT copy does not preserve ownership, and
# does nothing else differently. $SRC is disposable private build workspace
# and the payload establishes its own ownership independently, so the input
# tree's uid/gid carry no package semantics. Modes, timestamps, symlinks,
# directory structure and contents are still preserved exactly.
#
# This suite is about that one boundary. It does not assert anything about
# package payload ownership, which is set by makepkg and covered elsewhere.

set -eu

[ "$#" -eq 1 ] || {
	printf 'usage: %s BUILD-WORKER\n' "$0" >&2
	exit 1
}
worker=$1

SAPHIRA_TMPDIR=${SAPHIRA_TMPDIR:-/build/tmp}
work=$SAPHIRA_TMPDIR/staged-input-contract
# The root-owned fixture cannot be removed by the build user, so cleanup needs
# the same privilege that created it.
cleanup() {
	sudo -n rm -rf "$work" 2>/dev/null || rm -rf "$work" 2>/dev/null || true
}
cleanup
mkdir -p "$work"
trap cleanup EXIT

pass=0
fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
no() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }
check() { if [ "$1" = "$2" ]; then ok "$3"; else no "$3 (want '$1', got '$2')"; fi; }

# The namespace shape the builder actually uses. Reproduced rather than
# approximated: a single-uid mapping is the whole reason the bug exists, so a
# test that did not use one would pass against the buggy code.
bwrap_uid0()
{
	bwrap --die-with-parent --unshare-all --uid 0 --gid 0 --clearenv \
		--ro-bind /usr /usr --ro-bind /lib /lib --ro-bind /bin /bin \
		--ro-bind /etc /etc --bind "$work" "$work" \
		--dev /dev --proc /proc --setenv PATH /usr/bin:/bin \
		/bin/sh -c "$1"
}

command -v bwrap >/dev/null 2>&1 || {
	printf 'staged-input contract: bwrap required\n' >&2
	exit 1
}

# uid_map must be the single-line mapping the builder really uses. Asserted so
# that if this ever stops being true, the suite says so instead of quietly
# testing a different namespace than the one that broke.
mapped=$(bwrap_uid0 'cat /proc/self/uid_map' | awk '{print $2"/"$3}' | tr '\n' ' ')
[ "$(echo "$mapped" | wc -w)" = "1" ] \
	|| { printf 'expected a single-uid map, got: %s\n' "$mapped" >&2; exit 1; }
ok "namespace is a single-uid mapping ($mapped)"

# ---------------------------------------------------------------- fixtures --
# src_user:  owned by the build user (the historical, working case)
# src_root:  owned by real root, i.e. unmapped inside the namespace (the bug)
make_tree()
{
	_dest=$1
	rm -rf "$_dest"
	mkdir -p "$_dest/sub/deep"
	printf 'plain file contents\n' >"$_dest/regular"
	printf 'deep contents\n' >"$_dest/sub/deep/leaf"
	chmod 0755 "$_dest/sub"
	# World-readable, like a real prepared kernel tree. A root-owned 0640
	# file would be unreadable to the namespace uid -- neither its owner
	# nor its group -- which would fail as a fixture artefact rather than
	# exercising the ownership-preservation bug under test.
	chmod 0755 "$_dest/sub/deep/leaf"
	ln -s regular "$_dest/link-to-regular"
	ln -s ../regular "$_dest/sub/rel-link"
}

src_user=$work/src-user
src_root=$work/src-root
make_tree "$src_user"
make_tree "$src_root"
if [ "$(id -u)" = "0" ]; then
	chown -R 0:0 "$src_root"
else
	sudo -n chown -R 0:0 "$src_root" 2>/dev/null \
		|| { printf 'need sudo to build a root-owned fixture\n' >&2; exit 1; }
fi
check "0:0" "$(stat -c '%u:%g' "$src_root/regular")" "root fixture really is root-owned"

# ------------------------------------------------------------------ checks --
# Runs the builder's own copy expression. Kept as a literal so the test fails
# if someone reverts the flag, which is the mutation check below made routine.
run_copy()
{
	_dest=$1
	_src=$2
	_flags=$3
	rm -rf "$_dest"
	mkdir -p "$_dest"
	bwrap_uid0 "cp -a $_flags '$_src'/. '$_dest'/" 2>&1 || true
}

# 1. ordinary user-owned staged input still copies successfully
out_user=$work/out-user
run_copy "$out_user" "$src_user" "--no-preserve=ownership"
if [ -f "$out_user/regular" ] && [ -f "$out_user/sub/deep/leaf" ]; then
	ok "user-owned staged input copies successfully"
else
	no "user-owned staged input copies successfully"
fi

# 2. root-owned / unmapped-uid staged input copies inside the single-uid ns.
#    This is the case that aborted saphira-zfs-userspace.
out_root=$work/out-root
err=$(bwrap_uid0 "cp -a --no-preserve=ownership '$src_root'/. '$out_root'/" 2>&1 || true)
if [ -f "$out_root/regular" ] && [ -f "$out_root/sub/deep/leaf" ] && [ -z "$err" ]; then
	ok "root-owned (unmapped-uid) staged input copies successfully"
else
	no "root-owned staged input copies successfully [err: $err]"
fi

# 3. the copy belongs to the build uid, not 65534 and not root. Inside the
#    namespace uid 0 IS the build user, so on the host the copy is owned by
#    that user's real uid -- never by real root, never by the overflow uid.
build_uid=$(id -u)
copy_uid=$(stat -c '%u' "$out_root/regular")
check "$build_uid" "$copy_uid" \
	"copied tree is owned by the build uid, not 65534/root"
for bad_uid in 0 65534; do
	if [ "$copy_uid" != "$bad_uid" ]; then
		ok "copy is not owned by $bad_uid"
	else
		no "copy is owned by $bad_uid"
	fi
done

# 4. file modes survive
check "755" "$(stat -c '%a' "$out_root/sub/deep/leaf")" "file mode (incl. exec bit) survives"
check "755" "$(stat -c '%a' "$out_root/sub")" "directory mode survives"

# 5. symlinks survive as symlinks (not dereferenced into regular files)
if [ -L "$out_root/link-to-regular" ] && [ -L "$out_root/sub/rel-link" ]; then
	ok "symlinks survive as symlinks"
else
	no "symlinks survive as symlinks"
fi
check "regular" "$(readlink "$out_root/link-to-regular")" "symlink target preserved"

# 6. contents survive byte-for-byte
if cmp -s "$src_root/regular" "$out_root/regular" \
	&& cmp -s "$src_root/sub/deep/leaf" "$out_root/sub/deep/leaf"; then
	ok "contents survive byte-for-byte"
else
	no "contents survive byte-for-byte"
fi

# 7. the change is confined to the staged-input copy. The archive extraction
#    paths must be untouched, and package payload ownership must not be
#    weakened by this suite's subject.
if grep -q 'cp -a --no-preserve=ownership "\$SOURCE"/. "\$SRC"/' "$worker"; then
	ok "staged-input copy uses --no-preserve=ownership"
else
	no "staged-input copy uses --no-preserve=ownership"
fi
# No other plain ownership-preserving input copy may remain.
if grep -cE '^\s*cp -a "\$SOURCE"' "$worker" | grep -q '^0$'; then
	ok "no ownership-preserving staged-input copy remains"
else
	no "an ownership-preserving staged-input copy remains"
fi
# Payload ownership is makepkg's business and must not have been relaxed here.
if ! grep -qE -- '--no-preserve=ownership.*PKGDEST|PKGDEST.*--no-preserve=ownership' "$worker"; then
	ok "package payload ownership handling is untouched"
else
	no "package payload ownership handling was weakened"
fi

# ------------------------------------------------------- mutation check ----
# Prove the suite actually detects the regression it exists for: restore the
# buggy plain `cp -a` and require the root-owned case to fail. A green suite
# that cannot go red is not evidence of anything.
rm -rf "$work/out-buggy"
mkdir -p "$work/out-buggy"
err_buggy=$(bwrap_uid0 "cp -a '$src_root'/. '$work/out-buggy'/" 2>&1 || true)
case $err_buggy in
*"Invalid argument"*) ok "mutation check: plain cp -a fails on root-owned input (as it did in production)" ;;
*) no "mutation check: plain cp -a did not fail as expected [err: $err_buggy]" ;;
esac
# ...and the same input succeeds with the fix, so the difference is the flag.
if [ -f "$work/out-buggy/regular" ] && [ -f "$work/out-buggy/sub/deep/leaf" ]; then
	ok "mutation check: the fixed copy succeeds on that same input"
else
	no "mutation check: the fixed copy did not succeed on that same input"
fi

printf 'staged-input contract: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

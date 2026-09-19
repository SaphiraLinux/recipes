#!/bin/sh

# saphira-permissions V1 suite: reconcilers + full-system operation.
# Hermetic by construction - everything lands under a synthetic root
# in SAPHIRA_TMPDIR; the host account database and repository are
# checksummed before/after and must be identical.
#
# Two phases (ownership needs differ):
# - __userns: re-exec under unshare --user --map-root-user (genuine
#   mapped root: real chown/chmod/setcap on owned trees). Covers
#   modes, capabilities, rawsymlink safety, overrides, the
#   installed-database pass, and the capability sweep. Identities
#   here are root-owned only (a single-id user namespace cannot
#   chown to arbitrary IDs - kernel restriction, not tool gap).
# - __fakeroot: re-exec under fakeroot (ownership fiction, same
#   pattern as accounts.sh). Covers arbitrary-ID ownership
#   arguments for ensure-identity dir/file stanzas plus --check.
# file capabilities are NOT exercised under fakeroot (setcap needs
# real privilege: covered in __userns instead).
#
# usage: permissions.sh (no arguments)

set -eu

source_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

phase=${1:-driver}
case $phase in
driver | __userns | __fakeroot) ;;
*) printf 'usage: %s (no arguments)\n' "$0" >&2; exit 1 ;;
esac

test_tmp_base=${SAPHIRA_TMPDIR:-/build/test-tmp}
mkdir -p "$test_tmp_base"
test_root=$(mktemp -d "$test_tmp_base/saphira-permissions-test.XXXXXX")
export PERMISSIONS_TMPDIR=$test_root/tool-tmp
mkdir -p "$PERMISSIONS_TMPDIR"
trap 'rm -rf -- "$test_root"' EXIT HUP INT TERM

# Staged tool copies (sibling lookup for the override helper works
# from here with no installed saphira-permissions/baselayout).
TOOLS=$test_root/tools
mkdir -p "$TOOLS"
for tool in ensure-identity.sh ensure-fhs permissions-override.sh; do
	cp "$source_root/saphira-baselayout/files/libexec/$tool" "$TOOLS/$tool"
done
for tool in ensure-caps ensure-permissions; do
	cp "$source_root/saphira-permissions/files/libexec/$tool" "$TOOLS/$tool"
done
chmod 755 "$TOOLS"/ensure-identity.sh "$TOOLS"/ensure-fhs "$TOOLS"/ensure-caps "$TOOLS"/ensure-permissions

IDENTITY=$TOOLS/ensure-identity.sh
FHS=$TOOLS/ensure-fhs
CAPS=$TOOLS/ensure-caps
PERMS=$TOOLS/ensure-permissions

fail()
{
	printf '%s\n' "permissions test failure: $1" >&2
	exit 1
}

expect_rc()
{
	want=$1
	shift
	[ "$#" -gt 0 ] || fail "expect_rc without command"
	set +e
	"$@" >"$test_root/out.log" 2>"$test_root/err.log"
	rc=$?
	set -e
	[ "$rc" -eq "$want" ] || {
		printf '%s\n' "want rc $want, got $rc for: $*" >&2
		cat "$test_root/out.log" "$test_root/err.log" >&2
		exit 1
	}
}

expect_out()
{
	grep -F -q -e "$1" "$test_root/out.log" || grep -F -q -e "$1" "$test_root/err.log" || {
		printf '%s\n' "missing expected output: $1" >&2
		cat "$test_root/out.log" "$test_root/err.log" >&2
		exit 1
	}
}

expect_absent()
{
	if grep -F -q -e "$1" "$test_root/out.log" || grep -F -q -e "$1" "$test_root/err.log"; then
		printf '%s\n' "unexpected output present: $1" >&2
		cat "$test_root/out.log" "$test_root/err.log" >&2
		exit 1
	fi
}

# --- driver ------------------------------------------------------------
if [ "$phase" = driver ]; then
	host_before=$(sha256sum /lib/apk/db/installed /etc/apk/world /etc/passwd /etc/group)
	host_repo_before=$(find /out/stage4/packages/x86_64 -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort | sha256sum)
	command -v unshare >/dev/null 2>&1 || fail "user namespaces required (unshare)"
	command -v fakeroot >/dev/null 2>&1 || fail "fakeroot required"
	command -v setcap >/dev/null 2>&1 || fail "setcap required"
	# Capability vocabulary parity: the Python constructor list and
	# the shell override helper list are the two canonical copies.
	"${SAPHIRA_PYTHON:-python3}" - "$source_root" <<'PY'
import importlib.machinery
import importlib.util
import re
import sys
from pathlib import Path
source_root = Path(sys.argv[1])
loader = importlib.machinery.SourceFileLoader(
    "makepkg_perm", str(source_root / "saphira-packager/files/makepkg"))
spec = importlib.util.spec_from_loader("makepkg_perm", loader)
mk = importlib.util.module_from_spec(spec)
loader.exec_module(mk)
helper = (source_root / "saphira-baselayout/files/libexec/permissions-override.sh").read_text(encoding="utf-8")
match = re.search(r'^OVR_CAP_NAMES="([^"]*)"', helper, re.M)
assert match, "OVR_CAP_NAMES missing"
assert set(match.group(1).split()) == set(mk.SAPHIRA_CAP_NAMES), "capability list mismatch"
print("capability vocabulary parity: ok (41 names, both sides)")
PY
	HOME=$test_root unshare --user --map-root-user sh "$0" __userns
	fakeroot sh "$0" __fakeroot
	[ "$host_before" = "$(sha256sum /lib/apk/db/installed /etc/apk/world /etc/passwd /etc/group)" ] || fail "host databases changed"
	[ "$host_repo_before" = "$(find /out/stage4/packages/x86_64 -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort | sha256sum)" ] || fail "repository changed"
	printf '%s\n' 'permissions suite: OK (hermetic, host untouched)'
fi

if [ "$phase" = __fakeroot ]; then
	# --- arbitrary-ID ownership (fiction, args proven) ----------------
	R=$test_root/fakeroot
	mkdir -p "$R/etc" "$R/usr/bin" "$R/var/lib/svc150"
	printf 'root:x:0:0:root:/root:/bin/sh\n' >"$R/etc/passwd"
	printf 'root:x:0:\n' >"$R/etc/group"
	printf 'root:!:0:0:99999:7:::\n' >"$R/etc/shadow"
	printf 'x\n' >"$R/usr/bin/svcbin"
	chmod 755 "$R/usr/bin/svcbin"
	printf '%s\n' \
		'group svcgrp 150' \
		'user svcuser 150 svcgrp /nonexistent /sbin/nologin' \
		'dir /var/lib/svc150 0750 svcuser svcgrp' \
		'file /usr/bin/svcbin 0755 svcuser svcgrp' >"$R/frag"
	expect_rc 1 env SAPHIRA_ENSURE_ROOT="$R" "$IDENTITY" --check "$R/frag"
	expect_out "group svcgrp (150) would be created"
	expect_rc 0 env SAPHIRA_ENSURE_ROOT="$R" "$IDENTITY" "$R/frag"
	expect_out "directory /var/lib/svc150 ownership set to 150:150"
	expect_out "file /usr/bin/svcbin ownership set to 150:150"
	expect_rc 0 env SAPHIRA_ENSURE_ROOT="$R" "$IDENTITY" --check "$R/frag"
	expect_out "check: $R/frag clean"
	# Pin substitution wins over the fragment (args proven).
	mkdir -p "$R/etc/saphira/permissions/override.d"
	printf '%s\n' 'pin /var/lib/svc150 svcuser svcgrp 0700' >"$R/etc/saphira/permissions/override.d/admin.conf"
	expect_rc 0 env SAPHIRA_ENSURE_ROOT="$R" "$IDENTITY" "$R/frag"
	expect_out "pinned by administrator override"
	expect_rc 0 env SAPHIRA_ENSURE_ROOT="$R" "$IDENTITY" --check "$R/frag"
	# Ignore skips convergence (damage stays, run stays clean).
	chmod 777 "$R/usr/bin/svcbin"
	printf '%s\n' 'ignore /usr/bin/svcbin' >>"$R/etc/saphira/permissions/override.d/admin.conf"
	expect_rc 0 env SAPHIRA_ENSURE_ROOT="$R" "$IDENTITY" --check "$R/frag"
	expect_out "skipped (administrator override)"
	# Conflicting live identity reports drift instead of dying.
	printf 'other:x:999:999::/nonexistent:/sbin/nologin\n' >>"$R/etc/passwd"
	printf '%s\n' 'user other 150 svcgrp /nonexistent /sbin/nologin' >"$R/conflict"
	expect_rc 1 env SAPHIRA_ENSURE_ROOT="$R" "$IDENTITY" --check "$R/conflict"
	expect_out "user conflict: other exists with UID 999 (want 150)"
	printf '%s\n' 'permissions fakeroot phase: ok (arbitrary-ID args, pin, ignore, conflict)'
	exit 0
fi

# --- __userns phase ----------------------------------------------------
# Entered only via the driver (unshare --user --map-root-user):
# mapped root owns every synthetic tree, so chown/chmod/setcap
# are genuine syscalls, not fiction.
if [ "$phase" = __userns ]; then
[ "$(id -u)" -eq 0 ] || fail "__userns requires mapped root (run via the driver)"
R=$test_root/root
mkdir -p "$R/lib/apk/db" "$R/etc" "$R/usr/bin" "$R/usr/lib" "$R/etc/testpkg" \
	"$R/var/lib/testpkg" "$R/usr/share/saphira/accounts.d" \
	"$R/usr/share/saphira/fhs.d" "$R/usr/share/saphira/caps.d"
printf 'root:x:0:0:root:/root:/bin/sh\n' >"$R/etc/passwd"
printf 'root:x:0:\n' >"$R/etc/group"
printf 'root:!:0:0:99999:7:::\n' >"$R/etc/shadow"
chmod 600 "$R/etc/shadow"
# Crafted installed database: two packages, explicit modes, a
# symlink (777), a setuid binary, a protected config, dir modes.
cat >"$R/lib/apk/db/installed" <<'DBEOF'
C:Q1testpkg0000000000000000000000000000000=
P:testpkg
V:1-r0
A:x86_64
S:100
I:200
T:test package
U:https://example.invalid/
L:MIT
o:testpkg
t:1753401600
f:S
F:usr
F:usr/bin
R:demo
a:0:0:755
Z:Q1AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
R:plain
Z:Q1BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=
R:evil
Z:Q1CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC=
F:usr/lib
R:libx.so.1
a:0:0:777
Z:Q1DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD=
F:etc
F:etc/testpkg
R:node.conf
Z:Q1EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE=
F:var
F:var/lib
F:var/lib/testpkg
M:0:0:750
F:usr/share
F:usr/share/testshared
C:Q1testlib0000000000000000000000000000000=
P:testlib
V:2-r1
A:x86_64
S:50
I:60
T:library package without fragments
U:https://example.invalid/
L:MIT
o:testlib
t:1753401600
f:S
F:usr
F:usr/bin
R:tool
a:0:0:4755
Z:Q1FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF=
R:openbin
a:0:0:777
Z:Q1GGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGGG=
F:usr/share
F:usr/share/testshared
F:var
F:var/lib
F:var/lib/testpkg
M:0:0:700
DBEOF
mkdir -p "$R/usr/share/testshared"
chmod 755 "$R/usr/share/testshared"
printf 'x\n' >"$R/usr/bin/demo"
chmod 755 "$R/usr/bin/demo"
printf 'x\n' >"$R/usr/bin/plain"
chmod 644 "$R/usr/bin/plain"
printf 'x\n' >"$R/usr/bin/evil"
chmod 644 "$R/usr/bin/evil"
setcap cap_net_raw+ep "$R/usr/bin/evil"
printf 'x\n' >"$R/usr/bin/tool"
chmod 4755 "$R/usr/bin/tool"
# A genuine 0777 regular file (not a symlink): apk-tools masks
# file-type bits at archive read, so the database cannot tell it
# from a link — lstat at converge time must (this file converges,
# the libx.so.1 link below skips silently).
printf 'x\n' >"$R/usr/bin/openbin"
chmod 777 "$R/usr/bin/openbin"
printf 'x\n' >"$R/etc/testpkg/node.conf"
chmod 644 "$R/etc/testpkg/node.conf"
ln -s libx.so.1.2 "$R/usr/lib/libx.so.1"
# Fragments for testpkg only (testlib proves fragment-less packages
# still converge from database claims).
printf '%s\n' \
	'dir /var/lib/testpkg2 0755 root root' \
	'file /usr/bin/demo 0755 root root' >"$R/usr/share/saphira/accounts.d/testpkg"
printf '%s\n' \
	'dir /var/run/testpkg 0755 root root' \
	'rmdir-if-empty /run/testpkg' >"$R/usr/share/saphira/fhs.d/testpkg"
printf '%s\n' \
	'cap /usr/bin/demo cap_net_bind_service+ep' >"$R/usr/share/saphira/caps.d/testpkg"
# Ghost fragments for an UNINSTALLED package: never consulted, never
# stripped, never converged (plus a capped ghost binary below).
printf '%s\n' 'dir /var/lib/ghost 0755 root root' >"$R/usr/share/saphira/accounts.d/ghost"
printf '%s\n' 'dir /var/run/ghost 0755 root root' >"$R/usr/share/saphira/fhs.d/ghost"
printf '%s\n' 'cap /usr/bin/ghostbin cap_net_bind_service+ep' >"$R/usr/share/saphira/caps.d/ghost"
printf 'x\n' >"$R/usr/bin/ghostbin"
chmod 755 "$R/usr/bin/ghostbin"
setcap cap_net_bind_service+ep "$R/usr/bin/ghostbin"
# Administrator overrides: pin wins, ignore skips, unmatched warns.
mkdir -p "$R/etc/saphira/permissions/override.d"
printf '%s\n' \
	'pin /usr/bin/demo root root 0700' \
	'ignore /etc/demo.conf' \
	'ignore /no/such/claim' >"$R/etc/saphira/permissions/override.d/admin.conf"
# Application data inside a claimed dir: never walked, never touched.
printf 'precious\n' >"$R/var/lib/testpkg/custom"
chmod 777 "$R/var/lib/testpkg/custom"

# 1. pristine tree checks clean (pin already satisfied? demo is 755,
# so the pin fires on first apply; the pre-apply check must flag it).
expect_rc 1 "$PERMS" --system --root "$R" --check
expect_out "claim /usr/bin/demo is (0:0 755) want (0:0 700)"
expect_out "warning: override without a claim (inert, check spelling/scope): /no/such/claim"
expect_out "warning: override without a claim (inert, check spelling/scope): /etc/demo.conf"

# 2. damage everything the matrix covers.
chmod 777 "$R/usr/bin/demo"
chmod 600 "$R/var/lib/testpkg"
chmod 755 "$R/usr/bin/tool"
chmod 644 "$R/usr/bin/openbin"
chmod 700 "$R/usr/share/testshared"
setcap cap_net_bind_service+ep "$R/usr/bin/tool"
printf 'x\n' >"$R/etc/demo.conf"
chmod 600 "$R/etc/demo.conf"
chmod 600 "$R/etc/testpkg/node.conf"
rm -f "$R/var/lib/testpkg/custom"
printf 'precious\n' >"$R/var/lib/testpkg/custom"
chmod 777 "$R/var/lib/testpkg/custom"
rm -f "$R/usr/bin/plain"
ln -s /etc/passwd "$R/usr/bin/plain"
expect_rc 1 "$PERMS" --system --root "$R" --check
expect_out "claim /usr/bin/demo is (0:0 777) want (0:0 700)"
expect_out "claim /var/lib/testpkg is (0:0 600) want (0:0 750)"
expect_out "claim /usr/bin/tool is (0:0 755) want (0:0 4755)"
expect_out "claim /usr/bin/openbin is (0:0 644) want (0:0 777)"
expect_out "conflicting claims for /var/lib/testpkg"
# Identical co-owned claims collapse: exactly one drift line for
# the shared dir (not one per owning package).
[ "$(cat "$test_root/out.log" "$test_root/err.log" | grep -c 'claim /usr/share/testshared')" -eq 1 ] || fail "shared-dir claim reported more than once"
expect_out "protected: claim /etc/testpkg/node.conf is (0:0 600) want (0:0 644)"
expect_out "claim /usr/bin/plain is a symlink (refusing to follow)"
expect_out "undeclared capabilities: /usr/bin/tool"
expect_out "undeclared capabilities: /usr/bin/evil"
expect_out "unowned capped file (not packaged, never touched): /usr/bin/ghostbin"
expect_out "fragment(s) with drift"
# Ghost fragments stay silent (uninstalled scope exclusion): no
# fragment path may appear, while the ghost binary keeps its caps
# (out of scope: noticed, never stripped). The packaged libx.so.1
# symlink likewise stays silent (recorded-777 link skips without
# drift); only the attacked plain symlink reports.
expect_absent "accounts.d/ghost"
expect_absent "fhs.d/ghost"
expect_absent "caps.d/ghost"
expect_absent "claim /usr/lib/libx.so.1"

# 3. apply converges maximally but records the symlink attack.
expect_rc 1 "$PERMS" --system --root "$R" --apply
expect_out "failed: claim /usr/bin/plain is a symlink (refusing to follow)"
[ "$(stat -c '%a %u:%g' "$R/usr/bin/demo")" = "700 0:0" ] || fail "pin not converged: $(stat -c '%a %u:%g' "$R/usr/bin/demo")"
[ "$(stat -c '%a %u:%g' "$R/var/lib/testpkg")" = "750 0:0" ] || fail "dir mode not restored"
[ "$(stat -c '%a' "$R/usr/bin/tool")" = "4755" ] || fail "setuid not restored"
[ "$(stat -c '%a' "$R/usr/bin/openbin")" = "777" ] || fail "genuine 777 file not restored"
[ -z "$(getcap "$R/usr/bin/tool" 2>/dev/null)" ] || fail "rogue caps on packaged file not stripped"
[ "$(stat -c '%a' "$R/etc/testpkg/node.conf")" = "644" ] || fail "protected config not restored"
getcap "$R/usr/bin/demo" | grep -q cap_net_bind_service || fail "declared caps not restored"
# Never touched: application data, unpackaged capped files.
[ "$(stat -c '%a' "$R/var/lib/testpkg/custom")" = "777" ] || fail "application data was walked"
[ "$(cat "$R/var/lib/testpkg/custom")" = "precious" ] || fail "application data content changed"
[ -z "$(getcap "$R/usr/bin/evil" 2>/dev/null)" ] || fail "packaged undeclared caps not stripped"
getcap "$R/usr/bin/ghostbin" | grep -q cap_net_bind_service || fail "uninstalled package caps were stripped"
[ -L "$R/usr/lib/libx.so.1" ] || fail "packaged symlink was touched"
[ "$(stat -c '%a' "$R/etc/demo.conf")" = "600" ] || fail "ignored path was converged"

# 4. remove the attack symlink, restore the file, prove idempotence:
# apply converges, and the follow-up check reports exactly the one
# honest remaining drift (the testlib/testpkg packaging conflict can
# never satisfy both claims - that drift persists by design until
# the recipes agree).
rm -f "$R/usr/bin/plain"
printf 'x\n' >"$R/usr/bin/plain"
chmod 644 "$R/usr/bin/plain"
expect_rc 0 "$PERMS" --system --root "$R" --apply
expect_rc 1 "$PERMS" --system --root "$R" --check
expect_out "claim /var/lib/testpkg is (0:0 750) want (0:0 700)"
[ "$(grep -c 'drift:' "$test_root/err.log")" -eq 1 ] || fail "check is not down to the single conflict drift"

# 5. missing runtime dir is recreated by the fhs fragment.
rmdir "$R/var/run/testpkg"
expect_rc 1 "$PERMS" --system --root "$R" --check
expect_out "dir /var/run/testpkg is missing (would create)"
expect_rc 0 "$PERMS" --system --root "$R" --apply
[ -d "$R/var/run/testpkg" ] || fail "runtime dir not recreated"
expect_rc 1 "$PERMS" --system --root "$R" --check
expect_out "claim /var/lib/testpkg is (0:0 750) want (0:0 700)"

# 6. unit behaviours: unsafe roots, symlink fragments, guards.
expect_rc 1 "$FHS" --root "$R//x" "$R/usr/share/saphira/fhs.d/testpkg"
expect_out "refusing unsafe target root"
printf 'dir /var/run/u 0755 root root\n' >"$R/ufrag"
ln -sf "$R/ufrag" "$R/ufralink"
expect_rc 1 "$FHS" --root "$R" "$R/ufralink"
expect_out "must not be a symlink"
printf 'dir /usr 0755 root root\n' >"$R/rootfrag"
expect_rc 2 "$FHS" --root "$R" --check "$R/rootfrag"
expect_out "refusing operation on protected root"
printf 'bogus /var/run/u 0755 root root\n' >"$R/badoverride"
mkdir -p "$R/etc/saphira/permissions/override.d"
printf 'frobnicate /x\n' >"$R/etc/saphira/permissions/override.d/bad.conf"
expect_rc 2 "$FHS" --root "$R" --check "$R/ufrag"
expect_out "malformed stanza"
rm "$R/etc/saphira/permissions/override.d/bad.conf"
printf 'ignore /var/run/u\nignore /var/run/u\n' >"$R/etc/saphira/permissions/override.d/dup.conf"
expect_rc 2 "$FHS" --root "$R" --check "$R/ufrag"
expect_out "duplicate override"
rm "$R/etc/saphira/permissions/override.d/dup.conf"
printf 'cap /usr/bin/demo cap_bogus+ep\n' >"$R/badcap"
expect_rc 2 "$CAPS" --root "$R" --check "$R/badcap"
expect_out "invalid capability spec"
# pin-cap substitution converges foreign-to-fragment spec.
printf 'pin-cap /usr/bin/demo cap_net_raw+ep\n' >"$R/etc/saphira/permissions/override.d/pin.conf"
expect_rc 1 "$CAPS" --root "$R" --check "$R/usr/share/saphira/caps.d/testpkg"
expect_out "differs (want cap_net_raw+ep)"
rm "$R/etc/saphira/permissions/override.d/pin.conf"
# Exit-code contract: drift reports 1, execution errors report 2.
printf 'dir %s/contract 0755 root root\n' "$test_root" >"$R/contractfrag"
expect_rc 1 "$FHS" --root "$R" --check "$R/contractfrag"
printf 'frobnicate %s/contract\n' "$test_root" >"$R/contractfrag"
expect_rc 2 "$FHS" --root "$R" --check "$R/contractfrag"
expect_out "malformed stanza"

# 7. explicit empty --root is invalid everywhere (fail closed:
# an unset shell variable must never silently become /). Live
# operation passes NO --root flag at all (proved in 7b/7c below).
expect_rc 1 "$FHS" --root "" --check "$R/livefrag-shape"
expect_out "usage:"
expect_rc 1 "$CAPS" --root "" --check "$R/livecaps-shape"
expect_out "usage:"
expect_rc 1 "$PERMS" --system --root "" --check
expect_out "usage:"
# A bare --root with no value stays a usage error (ambiguity
# fails closed: `--root FRAGMENT` must never guess).
expect_rc 1 "$FHS" --root
expect_out "usage:"
expect_rc 1 "$CAPS" --root
expect_out "usage:"
expect_rc 1 "$PERMS" --system --root
expect_out "usage:"
# 7b. exact child argv (offline shape): logging shims prove the
# orchestrator passes --root "$ROOT" positionally correctly.
SHIM=$test_root/shims
mkdir -p "$SHIM"
cp "$TOOLS/permissions-override.sh" "$TOOLS/ensure-permissions" "$SHIM/"
chmod 755 "$SHIM/ensure-permissions"
for shim in ensure-identity.sh ensure-fhs ensure-caps; do
	cat >"$SHIM/$shim" <<EOF
#!/bin/sh
printf 'SHIM %s env=%s argv=%s\\n' "$shim" "\$SAPHIRA_ENSURE_ROOT" "\$*" >>"$test_root/shim.log"
exit 0
EOF
	chmod 755 "$SHIM/$shim"
done
: >"$test_root/shim.log"
# rc 1: the synthetic testpkg packaging conflict still drifts in
# the real DB pass (shims only stand in for fragment tools); the
# argv assertions below are the point of this run.
expect_rc 1 "$SHIM/ensure-permissions" --system --root "$R" --check
grep -F -q "SHIM ensure-fhs env= argv=--root $R --check $R/usr/share/saphira/fhs.d/testpkg" "$test_root/shim.log" || \
	fail "offline fhs argv wrong: $(cat "$test_root/shim.log")"
grep -F -q "SHIM ensure-caps env= argv=--root $R --check $R/usr/share/saphira/caps.d/testpkg" "$test_root/shim.log" || \
	fail "offline caps argv wrong: $(cat "$test_root/shim.log")"
grep -F -q "SHIM ensure-identity.sh env=$R argv=--check $R/usr/share/saphira/accounts.d/testpkg" "$test_root/shim.log" || \
	fail "offline identity argv/env wrong: $(cat "$test_root/shim.log")"
# 7c. live shape (no --root flag): the orchestrator must invoke
# children with NO --root argument. Proven with logging shims on
# the live database: children are no-ops and the database pass is
# stat-only, so this performs zero mutations (the rmdir probes
# live in sub-tools, which are shimmed away here); only the argv
# shape is asserted, never live drift counts. A mount-namespace
# cage was evaluated for this and rejected: this environment
# denies userns mounts (EPERM), and a fake live tree would prove
# less than the real argv path.
: >"$test_root/shim-live.log"
SHIMLIVE=$test_root/shims-live
mkdir -p "$SHIMLIVE"
cp "$TOOLS/permissions-override.sh" "$TOOLS/ensure-permissions" "$SHIMLIVE/"
chmod 755 "$SHIMLIVE/ensure-permissions"
for shim in ensure-identity.sh ensure-fhs ensure-caps; do
	cat >"$SHIMLIVE/$shim" <<EOF
#!/bin/sh
printf 'SHIM %s env=%s argv=%s\\n' "$shim" "\$SAPHIRA_ENSURE_ROOT" "\$*" >>"$test_root/shim-live.log"
exit 0
EOF
	chmod 755 "$SHIMLIVE/$shim"
done
set +e
"$SHIMLIVE/ensure-permissions" --system --check >"$test_root/shim-live-out.log" 2>"$test_root/shim-live-err.log"
liverc=$?
set -e
[ "$liverc" -eq 0 ] || [ "$liverc" -eq 1 ] || fail "live-shape probe exited $liverc"
grep -q "SHIM " "$test_root/shim-live.log" || fail "live-shape probe invoked no children"
if grep -F -q -e "--root" "$test_root/shim-live.log"; then
	printf '%s\n' "live-shape child got --root (must be absent):" >&2
	cat "$test_root/shim-live.log" >&2
	exit 1
fi
if grep -F -q "usage:" "$test_root/shim-live-out.log" "$test_root/shim-live-err.log"; then
	fail "live-shape hit usage error"
fi
printf '%s\n' "live-shape argv: ok (no --root in $(wc -l <"$test_root/shim-live.log") child invocations)"
# ensure-identity honors an empty environment root the same way
# (no --root flag exists there; unset means live). Not exercised
# here: check mode still takes the account lock, whose live file
# is writable only by genuine root (no sudo in suites, mapping
# does not confer host writes). The empty-value argv regression
# that bit production lives in the --root flag parsers, covered
# above for ensure-fhs/ensure-caps; identity takes no --root flag.

# 8. installed-binary orchestration: real published APKs
# (saphira-baselayout, saphira-permissions, chrony, openldap)
# installed with apk into a disposable root, then the INSTALLED
# ensure-permissions runs --system over multiple REAL fhs.d
# fragments. Proves the fragment path reaches ensure-fhs through
# the production argv.
# Exact-artifact variant: set PERM_APKS_UNDER_TEST to the full
# space-separated install set, using .apk file paths for artifacts
# under test (e.g. freshly built, unpublished r20/r3) and
# repository names for the rest; dependencies still resolve from
# the local repository.
R2=$test_root/apksys
mkdir -p "$R2/etc/apk/keys"
printf '/out/stage4/packages/hatched\n' >"$R2/etc/apk/repositories"
cp /etc/apk/keys/* "$R2/etc/apk/keys/" 2>/dev/null || true
printf 'x86_64\n' >"$R2/etc/apk/arch"
if [ -n "${PERM_APKS_UNDER_TEST:-}" ]; then
	# shellcheck disable=SC2086
	apk --root "$R2" --initdb --allow-untrusted --no-scripts add \
		$PERM_APKS_UNDER_TEST >"$test_root/apkadd.log" 2>&1 || {
		cat "$test_root/apkadd.log" >&2
		fail "apk install of under-test artifacts failed"
	}
else
	apk --root "$R2" --initdb --allow-untrusted --no-scripts add \
		saphira-baselayout saphira-permissions chrony openldap >"$test_root/apkadd.log" 2>&1 || {
		cat "$test_root/apkadd.log" >&2
		fail "apk install into disposable root failed"
	}
fi
test -x "$R2/usr/libexec/saphira/ensure-permissions" || fail "installed ensure-permissions missing"
test -f "$R2/usr/libexec/saphira/permissions-override.sh" || fail "installed override helper missing"
# Minimal account database so identity-owned fragments resolve
# (mirrors clean-root provisioning, not host state).
printf 'root:x:0:0:root:/root:/bin/sh\nldap:x:146:146:ldap:/var/lib/openldap:/sbin/nologin\n' >"$R2/etc/passwd"
printf 'root:x:0:\nldap:x:146:\n' >"$R2/etc/group"
printf 'root:!:0:0:99999:7:::\nldap:!:0:0:99999:7:::\n' >"$R2/etc/shadow"
chmod 600 "$R2/etc/shadow"
for frag in chrony openldap; do
	test -f "$R2/usr/share/saphira/fhs.d/$frag" || fail "real fragment $frag missing from disposable root"
done
expect_rc 1 "$R2/usr/libexec/saphira/ensure-permissions" --system --root "$R2" --check
expect_absent "usage:"
# Each real fragment was actually processed (drift or clean lines
# name it; a skipped fragment would be silent).
expect_out "fhs.d/chrony"
expect_out "fhs.d/openldap"
expect_out "fhs.d/saphira-baselayout"

# 9. failure propagation: a dying child must fail the run, never
# a misleading clean or a success-style summary. Proven twice:
# (a) with tree tools, where the exit-code contract holds
# (1 drift, 2 execution error); (b) with the installed binaries,
# where any nonzero child must still fail the run.
# (a) tree tools, synthetic root: malformed caps fragment for an
# installed package kills assessment...
printf 'frobnicate /usr/bin/testpkg\n' >"$R/usr/share/saphira/caps.d/testpkg"
expect_rc 2 "$PERMS" --system --root "$R" --check
expect_out "FAILED to execute"
expect_out "NOT a clean bill"
expect_absent "drift(s) in database claims"
rm "$R/usr/share/saphira/caps.d/testpkg"
# ...and in apply mode the failure is recorded with its exit code,
# not swallowed.
printf 'frobnicate /usr/bin/testpkg\n' >"$R/usr/share/saphira/caps.d/testpkg"
expect_rc 1 "$PERMS" --system --root "$R" --apply
expect_out "failed:"
expect_out "exited 1"
rm "$R/usr/share/saphira/caps.d/testpkg"
# (b) installed binaries, disposable root: any nonzero child fails
# the run (contract version installed there reports 1 for both
# drift and death, so assert nonzero, not the exact code).
mkdir -p "$R2/usr/share/saphira/caps.d"
printf 'frobnicate /usr/bin/chrony\n' >"$R2/usr/share/saphira/caps.d/chrony"
set +e
"$R2/usr/libexec/saphira/ensure-permissions" --system --root "$R2" --check >"$test_root/out.log" 2>"$test_root/err.log"
rc=$?
set -e
[ "$rc" -ne 0 ] || fail "installed orchestrator swallowed a dead child (rc 0)"
grep -F -q -e "chrony" "$test_root/out.log" "$test_root/err.log" || fail "dead child left no trace"
rm "$R2/usr/share/saphira/caps.d/chrony"

printf '%s\n' 'permissions userns phase: ok (matrix, sweep, overrides, guards, idempotence)'

fi

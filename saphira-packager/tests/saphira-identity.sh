#!/bin/sh

# saphira-identity reconcile unit tests: account-database migration
# only (passwd/group, gshadow rows when present; shadow untouched;
# filesystem ownership never involved). Rootless by construction: all
# mutation lands under caller-supplied SAPHIRA_ENSURE_ROOT roots, so
# no sudo, no fakeroot, no apk, and no package is ever built here.
#
# Usage: saphira-identity.sh (no arguments)

set -eu

[ "$#" -eq 0 ] || {
	printf 'usage: %s (no arguments)\n' "$0" >&2
	exit 1
}

source_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tool=$source_root/saphira-baselayout/files/sbin/saphira-identity
test -f "$tool" || {
	printf 'tool is missing: %s\n' "$tool" >&2
	exit 1
}
test_tmp_base=${SAPHIRA_TMPDIR:-/build/test-tmp}
mkdir -p "$test_tmp_base"
test_root=$(mktemp -d "$test_tmp_base/saphira-identity-test.XXXXXX")
export SAPHIRA_TMPDIR=$test_root/tool-tmp
mkdir -p "$SAPHIRA_TMPDIR"
trap 'rm -rf -- "$test_root"' EXIT HUP INT TERM
host_before=$(sha256sum /etc/passwd /etc/group)

identify()
{
	root=$1
	shift
	SAPHIRA_ENSURE_ROOT=$root sh "$tool" "$@"
}

seed_root()
{
	root=$1
	mkdir -p "$root/etc" "$root/usr/share/saphira/accounts.d"
	printf 'root:x:0:0:root:/root:/bin/bash\n' > "$root/etc/passwd"
	printf 'root:x:0:\nman:x:13:\n' > "$root/etc/group"
	printf 'root:$6$rounds=5000$lockedtest:1:0:99999:7:::\n' > "$root/etc/shadow"
	printf 'root::0:\nman::13:\n' > "$root/etc/gshadow"
}

seed_mig()
{
	root=$1
	seed_root "$root"
	printf 'muser:x:988:988:muser:/var/lib/m:/sbin/nologin\n' >> "$root/etc/passwd"
	printf 'mgroup:x:988:\n' >> "$root/etc/group"
	printf 'muser:!:0:0:99999:7:::\n' >> "$root/etc/shadow"
	printf 'mgroup::988:\n' >> "$root/etc/gshadow"
	printf 'user muser 127 mgroup /var/lib/m /sbin/nologin\ngroup mgroup 127\n' > "$root/usr/share/saphira/accounts.d/migpkg"
	printf '# history\nlegacy user muser 988 988\nlegacy group mgroup 988\n' > "$root/usr/share/saphira/accounts.d/migpkg.legacy"
}

R=$test_root/root
seed_mig "$R"

# 1. Unknown package refuses.
if identify "$R" reconcile nosuchpkg > "$test_root/1.log" 2>&1; then
	printf '%s\n' 'unknown package unexpectedly accepted' >&2
	exit 1
fi
grep 'no installed declaration' "$test_root/1.log" >/dev/null

# 2. Package without legacy history is a clean no-op.
mkdir -p "$R/usr/share/saphira/accounts.d"
printf 'user plainuser 140 plaingroup /var/lib/plain /sbin/nologin\ngroup plaingroup 140\n' > "$R/usr/share/saphira/accounts.d/plainpkg"
identify "$R" reconcile plainpkg > "$test_root/2.log" 2>&1
grep 'no legacy entries for plainpkg' "$test_root/2.log" >/dev/null

# 3. Dry-run prints the plan and changes nothing.
before_dry=$(sha256sum "$R/etc/passwd" "$R/etc/group" "$R/etc/shadow" "$R/etc/gshadow")
identify "$R" reconcile migpkg > "$test_root/3.log" 2>&1
grep 'dry-run migration plan for migpkg' "$test_root/3.log" >/dev/null
grep 'user muser 988:988 127:127' "$test_root/3.log" >/dev/null
grep 'group mgroup 988 127' "$test_root/3.log" >/dev/null
grep 're-run with --apply' "$test_root/3.log" >/dev/null
[ "$(sha256sum "$R/etc/passwd" "$R/etc/group" "$R/etc/shadow" "$R/etc/gshadow")" = "$before_dry" ]
test ! -d "$R/var/lib/saphira/identity-backups"

# 4. --apply renumbers passwd/group (+gshadow), leaves shadow alone,
# backs up first, and verifies.
identify "$R" reconcile migpkg --apply > "$test_root/4.log" 2>&1
grep '^muser:x:127:127:muser:/var/lib/m:/sbin/nologin$' "$R/etc/passwd" >/dev/null
grep '^mgroup:x:127:$' "$R/etc/group" >/dev/null
grep '^muser:!:0:0:99999:7:::$' "$R/etc/shadow" >/dev/null
grep '^mgroup::127:$' "$R/etc/gshadow" >/dev/null
grep 'databases backed up to' "$test_root/4.log" >/dev/null
grep 'user muser migrated to 127:127' "$test_root/4.log" >/dev/null
grep 'group mgroup migrated to 127' "$test_root/4.log" >/dev/null
backup=$(grep 'databases backed up to' "$test_root/4.log" | sed 's/.* //')
grep '^muser:x:988:988:' "$backup/passwd" >/dev/null
grep '^mgroup:x:988:$' "$backup/group" >/dev/null
test -f "$backup/shadow"
[ "$(stat -c '%a' "$backup")" = "700" ]
[ "$(grep -c '' "$R/etc/passwd")" -eq 2 ]

# 5. Re-run is a converged no-op (already migrated skips, exit 0).
identify "$R" reconcile migpkg --apply > "$test_root/5.log" 2>&1
grep 'already migrated' "$test_root/5.log" >/dev/null
grep 'nothing to do' "$test_root/5.log" >/dev/null

# 6. Occupied target refuses before any write.
R2=$test_root/root2
seed_mig "$R2"
printf 'squatter:x:127:127:squatter:/var/lib/sq:/sbin/nologin\n' >> "$R2/etc/passwd"
printf 'squatter:!:0:0:99999:7:::\n' >> "$R2/etc/shadow"
before_sq=$(sha256sum "$R2/etc/passwd" "$R2/etc/group" "$R2/etc/shadow" "$R2/etc/gshadow")
if identify "$R2" reconcile migpkg --apply > "$test_root/6.log" 2>&1; then
	printf '%s\n' 'occupied target unexpectedly accepted' >&2
	exit 1
fi
grep 'already owned by user squatter' "$test_root/6.log" >/dev/null
[ "$(sha256sum "$R2/etc/passwd" "$R2/etc/group" "$R2/etc/shadow" "$R2/etc/gshadow")" = "$before_sq" ]
test ! -d "$R2/var/lib/saphira/identity-backups"

# 7. Unrecognised state (matches neither declared nor legacy) refuses.
R3=$test_root/root3
seed_mig "$R3"
sed -i 's/^muser:x:988:988:/muser:x:666:666:/' "$R3/etc/passwd"
if identify "$R3" reconcile migpkg --apply > "$test_root/7.log" 2>&1; then
	printf '%s\n' 'unrecognised state unexpectedly accepted' >&2
	exit 1
fi
grep 'matches neither the declared' "$test_root/7.log" >/dev/null

# 8. Absent legacy identities skip cleanly (vacuous migration).
R4=$test_root/root4
seed_root "$R4"
printf 'user ghostuser 129 ghostgroup /var/lib/ghost /sbin/nologin\ngroup ghostgroup 129\n' > "$R4/usr/share/saphira/accounts.d/ghostpkg"
printf 'legacy user ghostuser 989 989\nlegacy group ghostgroup 989\n' > "$R4/usr/share/saphira/accounts.d/ghostpkg.legacy"
identify "$R4" reconcile ghostpkg --apply > "$test_root/8.log" 2>&1
grep 'absent; nothing to migrate' "$test_root/8.log" >/dev/null
grep 'nothing to do' "$test_root/8.log" >/dev/null
test "$(grep -c '^ghostuser:' "$R4/etc/passwd")" -eq 0

# 9. Malformed sidecars and reserved legacy refuse.
printf 'legacy user\n' > "$R4/usr/share/saphira/accounts.d/ghostpkg.legacy"
if identify "$R4" reconcile ghostpkg --apply > "$test_root/9.log" 2>&1; then
	printf '%s\n' 'malformed sidecar unexpectedly accepted' >&2
	exit 1
fi
grep 'legacy user needs 3 fields' "$test_root/9.log" >/dev/null
printf 'legacy user root 0 0\n' > "$R4/usr/share/saphira/accounts.d/ghostpkg.legacy"
if identify "$R4" reconcile ghostpkg --apply > "$test_root/9b.log" 2>&1; then
	printf '%s\n' 'reserved legacy unexpectedly accepted' >&2
	exit 1
fi
grep 'never a legacy identity' "$test_root/9b.log" >/dev/null

# 10. Missing gshadow is fine (skipped, not required).
R5=$test_root/root5
seed_mig "$R5"
rm "$R5/etc/gshadow"
identify "$R5" reconcile migpkg --apply > "$test_root/10.log" 2>&1
grep '^muser:x:127:127:' "$R5/etc/passwd" >/dev/null
grep '^mgroup:x:127:$' "$R5/etc/group" >/dev/null

[ "$host_before" = "$(sha256sum /etc/passwd /etc/group)" ]
printf '%s\n' 'saphira-identity reconcile unit tests (rootless): unknown refusal, no-history no-op, dry-run plan, apply renumber+backup+verify, converged re-run, occupied-target refusal, unrecognised-state refusal, absent skip, malformed/reserved refusal, gshadow-absent tolerance: OK'

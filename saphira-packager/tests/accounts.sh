#!/bin/sh

# Account reconciler unit tests: ensure-identity.sh only. Rootless by
# construction - the helper runs under fakeroot (unprivileged syscall
# interception, no sudo, no namespaces), so no sudo, no apk, and no
# package is ever built here. This suite tests the reconciler's logic;
# the constructor is tested by makepkg.sh, publication by
# publication.sh, and end-to-end proof belongs to the real builder
# pipeline plus the install boundary - never to this file.
#
# Honest limitation, stated plainly: fakeroot intercepts the ownership
# calls, so these tests prove the helper attempts the right operations
# with the right arguments (verified through intercepted stat). The
# genuine chown is proven later on a real target through the install
# boundary. The lock file is real, so serialization IS genuinely
# exercised here.
#
# Usage: accounts.sh (no arguments)

set -eu

# Single shared ownership fiction for the whole run: re-exec once under
# fakeroot so every helper run and every asserting stat sees the same
# intercepted database (separate fakeroot invocations would each start
# empty). Zero privilege throughout; see header note.
if [ -z "${SAPHIRA_ACCOUNTS_FAKED:-}" ]; then
	SAPHIRA_ACCOUNTS_FAKED=1 exec fakeroot "$0" "$@"
fi

[ "$#" -eq 0 ] || {
	printf 'usage: %s (no arguments)\n' "$0" >&2
	exit 1
}

source_root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
helper=$source_root/saphira-baselayout/files/libexec/ensure-identity.sh
test -f "$helper" || {
	printf 'helper is missing: %s\n' "$helper" >&2
	exit 1
}
command -v fakeroot >/dev/null 2>&1 || {
	printf 'accounts test requires fakeroot (unprivileged ownership fiction)\n' >&2
	exit 1
}
test_root=$(mktemp -d /tmp/saphira-accounts-test.XXXXXX)
trap 'rm -rf -- "$test_root"' EXIT HUP INT TERM
host_before=$(sha256sum /etc/passwd /etc/group)

# All commands below already run inside the single shared fakeroot
# session (see top re-exec), so chown/stat exercise the helper's full
# ownership paths with zero privilege. All mutation lands under the
# caller-supplied root.
as_root_cmd()
{
	root=$1
	shift
	SAPHIRA_ENSURE_ROOT=$root "$@"
}

as_root()
{
	root=$1
	shift
	as_root_cmd "$root" sh "$helper" "$@"
}

# --- fixture account database (root + base-seeded man group, nothing else)
seed_root()
{
	root=$1
	mkdir -p "$root/etc"
	printf 'root:x:0:0:root:/root:/bin/bash\n' > "$root/etc/passwd"
	printf 'root:x:0:\nman:x:13:\n' > "$root/etc/group"
	printf 'root:$6$rounds=5000$lockedtest:1:0:99999:7:::\n' > "$root/etc/shadow"
	printf '# name\ttype\tid\tprimary-group\thome\tshell\tsupplementary-groups\nroot\tuser\t0\troot\t/root\t/bin/bash\twheel\nroot\tgroup\t0\t-\t-\t-\t-\nman\tgroup\t13\t-\t-\t-\t-\n' > "$root/accounts.tsv"
}

R=$test_root/root
seed_root "$R"
printf 'user svcuser 650 svcgroup /var/lib/svc /sbin/nologin\ngroup svcgroup 650\ndir /var/lib/svc 0755 svcuser svcgroup\n' > "$test_root/frag"

# 1. Fresh creation: append-at-end, locked shadow, leaf ownership.
as_root "$R" "$test_root/frag" > "$test_root/1.log" 2>&1
grep '^svcuser:x:650:650:svcuser:/var/lib/svc:/sbin/nologin$' "$R/etc/passwd" >/dev/null
grep '^svcgroup:x:650:$' "$R/etc/group" >/dev/null
grep '^svcuser:!:0:0:99999:7:::$' "$R/etc/shadow" >/dev/null
grep '^root:\$6\$rounds=5000\$lockedtest:' "$R/etc/shadow" >/dev/null
[ "$(stat -c '%u:%g %a' "$R/var/lib/svc")" = "650:650 755" ]
[ "$(head -1 "$R/etc/passwd")" = "root:x:0:0:root:/root:/bin/bash" ]
after_create=$(sha256sum "$R/etc/passwd" "$R/etc/group" "$R/etc/shadow")

# 2. Idempotent re-run: exit 0, byte-identical databases.
as_root "$R" "$test_root/frag" > "$test_root/2.log" 2>&1
[ "$(sha256sum "$R/etc/passwd" "$R/etc/group" "$R/etc/shadow")" = "$after_create" ]

# 3. Concurrent runs serialize: 4 parallel invocations, all exit 0,
# single entries apiece.
R2=$test_root/root2
seed_root "$R2"
for i in 1 2 3 4; do
	as_root "$R2" "$test_root/frag" > "$test_root/par.$i.log" 2>&1 &
done
wait
[ "$(grep -c '^svcuser:' "$R2/etc/passwd")" -eq 1 ]
[ "$(grep -c '^svcgroup:' "$R2/etc/group")" -eq 1 ]
[ "$(grep -c '^svcuser:' "$R2/etc/shadow")" -eq 1 ]

# 4. UID conflict (different name, same UID) fails closed.
printf 'user impostor 650 svcgroup /var/lib/imp /sbin/nologin\ngroup svcgroup 650\n' > "$test_root/evil"
if as_root "$R" "$test_root/evil" > "$test_root/4.log" 2>&1; then
	printf '%s\n' 'UID conflict unexpectedly accepted' >&2
	exit 1
fi
grep 'UID conflict' "$test_root/4.log" >/dev/null

# 5. Name conflict (same name, different UID) fails closed.
printf 'user svcuser 651 svcgroup /var/lib/svc /sbin/nologin\ngroup svcgroup 650\n' > "$test_root/evil2"
if as_root "$R" "$test_root/evil2" > "$test_root/5.log" 2>&1; then
	printf '%s\n' 'name conflict unexpectedly accepted' >&2
	exit 1
fi
grep 'user conflict' "$test_root/5.log" >/dev/null

# 6. A usable password hash is never touched: fatal, hash byte-identical.
# (Setup swaps only the hash field - the separator colons stay exactly
# where they were; a stray colon here would corrupt the fixture DB.)
sed -i 's/^svcuser:!/svcuser:$6$livehash/' "$R/etc/shadow"
if as_root "$R" "$test_root/frag" > "$test_root/6.log" 2>&1; then
	printf '%s\n' 'usable shadow hash unexpectedly touched' >&2
	exit 1
fi
grep 'usable password hash' "$test_root/6.log" >/dev/null
grep '^svcuser:\$6\$livehash:' "$R/etc/shadow" >/dev/null
sed -i 's/^svcuser:\$6\$livehash/svcuser:!/' "$R/etc/shadow"
grep '^svcuser:!:0:0:99999:7:::$' "$R/etc/shadow" >/dev/null

# 7. Malformed fragments fail closed (bad stanza, bad UID, relative home).
printf 'frobnicate svcuser\n' > "$test_root/bad1"
printf 'user svcuser abc svcgroup /var/lib/svc /sbin/nologin\ngroup svcgroup 650\n' > "$test_root/bad2"
printf 'user svcuser 650 svcgroup var/lib/svc /sbin/nologin\ngroup svcgroup 650\n' > "$test_root/bad3"
for bad in bad1 bad2 bad3; do
	if as_root "$R" "$test_root/$bad" > "$test_root/7.$bad.log" 2>&1; then
		printf '%s\n' "malformed fragment $bad unexpectedly accepted" >&2
		exit 1
	fi
done

# 8. Base-seeded primary group materializes (the man/13 case); a
# primary group that is nowhere (fragment, target, seed) fails closed.
printf 'user man 65 man /var/cache/man /sbin/nologin\ndir /var/cache/man 0755 man man\n' > "$test_root/manfrag"
as_root "$R" "$test_root/manfrag" >/dev/null 2>&1
grep '^man:x:65:13:man:/var/cache/man:/sbin/nologin$' "$R/etc/passwd" >/dev/null
printf 'user ghost 652 nosuchgroup /var/lib/ghost /sbin/nologin\n' > "$test_root/ghost"
if as_root "$R" "$test_root/ghost" > "$test_root/8.log" 2>&1; then
	printf '%s\n' 'undeclared primary group unexpectedly accepted' >&2
	exit 1
fi
grep 'not declared, present, or base-seeded' "$test_root/8.log" >/dev/null

# 8b. Packaged range: creation at UID/GID 888+ refuses (local-user-service
# territory 888..999, humans 1000+); the error names the range.
printf 'user biguser 900 biggroup /var/lib/big /sbin/nologin\ngroup biggroup 900\n' > "$test_root/bigrange"
if as_root "$R" "$test_root/bigrange" > "$test_root/8b.log" 2>&1; then
	printf '%s\n' 'out-of-range identity unexpectedly created' >&2
	exit 1
fi
grep 'outside packaged range 0..887' "$test_root/8b.log" >/dev/null
test "$(grep -c '^biguser:' "$R/etc/passwd")" -eq 0

# 8d. Reserved identities are untouchable in BOTH modes: a fragment
# naming root/wheel or allocating ID 0 is refused before any write,
# and the databases stay byte-identical.
printf 'user root 0 root /root /bin/bash\ngroup root 0\n' > "$test_root/rootfrag"
before_root=$(sha256sum "$R/etc/passwd" "$R/etc/group" "$R/etc/shadow")
if as_root "$R" "$test_root/rootfrag" > "$test_root/8d.log" 2>&1; then
	printf '%s\n' 'root fragment unexpectedly accepted (ensure)' >&2
	exit 1
fi
grep 'reserved system identity' "$test_root/8d.log" >/dev/null
if as_root "$R" --disable "$test_root/rootfrag" > "$test_root/8d-dis.log" 2>&1; then
	printf '%s\n' 'root fragment unexpectedly accepted (disable)' >&2
	exit 1
fi
grep 'reserved system identity' "$test_root/8d-dis.log" >/dev/null
[ "$(sha256sum "$R/etc/passwd" "$R/etc/group" "$R/etc/shadow")" = "$before_root" ]
printf 'user toor 0 toor /var/empty /sbin/nologin\ngroup toor 1\n' > "$test_root/zerofrag"
if as_root "$R" "$test_root/zerofrag" > "$test_root/8d-zero.log" 2>&1; then
	printf '%s\n' 'UID-0 fragment unexpectedly accepted' >&2
	exit 1
fi
grep 'ID 0 is reserved' "$test_root/8d-zero.log" >/dev/null
[ "$(sha256sum "$R/etc/passwd" "$R/etc/group" "$R/etc/shadow")" = "$before_root" ]
# Foundational groups are typed reservations: root/wheel/spokes names
# and GIDs 0/1/2 refuse in both modes, under any name.
printf 'user svcuser2 651 spokes /var/lib/svc2 /sbin/nologin\ngroup spokes 2\n' > "$test_root/spokesfrag"
if as_root "$R" "$test_root/spokesfrag" > "$test_root/8d-spokes.log" 2>&1; then
	printf '%s\n' 'spokes fragment unexpectedly accepted (ensure)' >&2
	exit 1
fi
grep 'reserved foundation' "$test_root/8d-spokes.log" >/dev/null
if as_root "$R" --disable "$test_root/spokesfrag" > "$test_root/8d-spokes-dis.log" 2>&1; then
	printf '%s\n' 'spokes fragment unexpectedly accepted (disable)' >&2
	exit 1
fi
grep 'reserved foundation' "$test_root/8d-spokes-dis.log" >/dev/null
printf 'group shadowsys 1\n' > "$test_root/gid1frag"
if as_root "$R" "$test_root/gid1frag" > "$test_root/8d-gid1.log" 2>&1; then
	printf '%s\n' 'GID-1 fragment unexpectedly accepted' >&2
	exit 1
fi
grep 'reserved foundation' "$test_root/8d-gid1.log" >/dev/null
[ "$(sha256sum "$R/etc/passwd" "$R/etc/group" "$R/etc/shadow")" = "$before_root" ]

# 8c. Hand-provisioned local accounts converge: a qmail-style fixed
# identity created by the local admin with matching attributes makes
# the fragment a silent no-op instead of blocking the install.
printf 'qdgrp:x:779:\n' >> "$R/etc/group"
printf 'qmaild:x:779:779:qmaild:/var/lib/qmail:/sbin/nologin\n' >> "$R/etc/passwd"
printf 'qmaild:!:0:0:99999:7:::\n' >> "$R/etc/shadow"
printf 'user qmaild 779 qdgrp /var/lib/qmail /sbin/nologin\ngroup qdgrp 779\ndir /var/lib/qmail 0755 qmaild qdgrp\n' > "$test_root/qmailfrag"
as_root "$R" "$test_root/qmailfrag" > "$test_root/8c.log" 2>&1
[ "$(grep -c '^qmaild:' "$R/etc/passwd")" -eq 1 ]
[ "$(grep -c '^qdgrp:' "$R/etc/group")" -eq 1 ]
grep '^qmaild:!:0:0:99999:7:::$' "$R/etc/shadow" >/dev/null

# 9. Directory reconciliation is non-recursive: the leaf is fixed, the
# existing tree (ownership and content) is untouched.
mkdir -p "$R/var/lib/svc/sub"
printf '%s\n' precious > "$R/var/lib/svc/sub/data"
as_root_cmd "$R" chown 0:0 "$R/var/lib/svc" "$R/var/lib/svc/sub"
as_root "$R" "$test_root/frag" >/dev/null 2>&1
[ "$(stat -c '%u:%g' "$R/var/lib/svc")" = "650:650" ]
[ "$(stat -c '%u:%g' "$R/var/lib/svc/sub")" = "0:0" ]
[ "$(cat "$R/var/lib/svc/sub/data")" = "precious" ]

# 10. Disable sanitizes without deleting: corrupt the installed
# identity into login-capable shape (usable hash + real shell), then
# --disable must lock it again and restore nologin while preserving
# UID, GID, home, and every other field. State is untouched.
sed -i 's/^svcuser:!/svcuser:$6$loginready/' "$R/etc/shadow"
sed -i 's|^svcuser:\([^:]*\):\([^:]*\):\([^:]*\):\([^:]*\):\([^:]*\):.*|svcuser:\1:\2:\3:\4:\5:/bin/bash|' "$R/etc/passwd"
grep '^svcuser:\$6\$loginready:' "$R/etc/shadow" >/dev/null
grep '^svcuser:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:/bin/bash$' "$R/etc/passwd" >/dev/null
printf '%s\n' statedata | tee "$R/var/lib/svc/state" >/dev/null
as_root "$R" --disable "$test_root/frag" > "$test_root/10.log" 2>&1
grep '^svcuser:x:650:650:svcuser:/var/lib/svc:/sbin/nologin$' "$R/etc/passwd" >/dev/null
grep '^svcuser:!:0:0:99999:7:::$' "$R/etc/shadow" >/dev/null
grep '^svcgroup:x:650:$' "$R/etc/group" >/dev/null
[ "$(cat "$R/var/lib/svc/state")" = "statedata" ]
[ "$(cat "$R/var/lib/svc/sub/data")" = "precious" ]
after_disable=$(sha256sum "$R/etc/passwd" "$R/etc/group" "$R/etc/shadow")

# 11. Repeat disable is harmless: byte-identical databases.
as_root "$R" --disable "$test_root/frag" > "$test_root/11.log" 2>&1
[ "$(sha256sum "$R/etc/passwd" "$R/etc/group" "$R/etc/shadow")" = "$after_disable" ]

# 12. Disable of an absent identity is a no-op (and creates nothing).
printf 'user goneuser 651 gonegroup /var/lib/gone /sbin/nologin\ngroup gonegroup 651\n' > "$test_root/gonefrag"
as_root "$R" --disable "$test_root/gonefrag" > "$test_root/12.log" 2>&1
test "$(grep -c '^goneuser:' "$R/etc/passwd")" -eq 0
test "$(grep -c '^gonegroup:' "$R/etc/group")" -eq 0
test "$(grep -c '^goneuser:' "$R/etc/shadow")" -eq 0

# 13. Disable fails closed on conflict and writes nothing: an unrelated
# account sharing only the name (different UID) must be left exactly
# as found.
printf 'user svcuser 652 svcgroup /var/lib/svc /sbin/nologin\ngroup svcgroup 650\n' > "$test_root/evilfrag"
before_evil=$(sha256sum "$R/etc/passwd" "$R/etc/group" "$R/etc/shadow")
if as_root "$R" --disable "$test_root/evilfrag" > "$test_root/13.log" 2>&1; then
	printf '%s\n' 'disable UID conflict unexpectedly accepted' >&2
	exit 1
fi
grep 'different UID' "$test_root/13.log" >/dev/null
[ "$(sha256sum "$R/etc/passwd" "$R/etc/group" "$R/etc/shadow")" = "$before_evil" ]
printf 'user svcuser 650 wronggroup /var/lib/svc /sbin/nologin\ngroup wronggroup 649\n' > "$test_root/evilfrag2"
if as_root "$R" --disable "$test_root/evilfrag2" > "$test_root/13b.log" 2>&1; then
	printf '%s\n' 'disable GID conflict unexpectedly accepted' >&2
	exit 1
fi
grep 'different primary group' "$test_root/13b.log" >/dev/null
[ "$(sha256sum "$R/etc/passwd" "$R/etc/group" "$R/etc/shadow")" = "$before_evil" ]

# 14. Reinstall after disable converges onto the same UID/GID: ensure
# restores the canonical locked/nologin identity in place.
as_root "$R" "$test_root/frag" > "$test_root/14.log" 2>&1
grep '^svcuser:x:650:650:svcuser:/var/lib/svc:/sbin/nologin$' "$R/etc/passwd" >/dev/null
grep '^svcuser:!:0:0:99999:7:::$' "$R/etc/shadow" >/dev/null
[ "$(grep -c '^svcuser:' "$R/etc/passwd")" -eq 1 ]

[ "$host_before" = "$(sha256sum /etc/passwd /etc/group)" ]
printf '%s\n' 'account reconciler unit tests (rootless): creation, idempotency, serialization, conflict refusal, range refusal, reserved-identity refusal, local convergence, credential refusal, disable/restore, idempotent disable, absent no-op, disable conflict refusal, state retention, reinstall convergence: OK'

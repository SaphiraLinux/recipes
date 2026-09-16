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
test_tmp_base=${SAPHIRA_TMPDIR:-/build/test-tmp}
mkdir -p "$test_tmp_base"
test_root=$(mktemp -d "$test_tmp_base/saphira-accounts-test.XXXXXX")
export SAPHIRA_TMPDIR=$test_root/tool-tmp
mkdir -p "$SAPHIRA_TMPDIR"
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

# 2b. Mode hygiene: databases created under a strict umask (600 group)
# heal to 644/644/600 on the next run (Hatched 2026-09: /etc/group mode
# 600 broke every non-root group lookup).
R3=$test_root/root3
seed_root "$R3"
chmod 600 "$R3/etc/passwd" "$R3/etc/group" "$R3/etc/shadow"
as_root "$R3" "$test_root/frag" > "$test_root/2b.log" 2>&1
[ "$(stat -c '%a' "$R3/etc/passwd")" = "644" ]
[ "$(stat -c '%a' "$R3/etc/group")" = "644" ]
[ "$(stat -c '%a' "$R3/etc/shadow")" = "600" ]
grep '^svcgroup:x:650:$' "$R3/etc/group" >/dev/null

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

# 13. Disable never blocks on drift: a name sharing only the name
# (different UID) is foreign - warn, leave byte-untouched, exit 0.
printf 'user svcuser 652 svcgroup /var/lib/svc /sbin/nologin\ngroup svcgroup 650\n' > "$test_root/evilfrag"
before_evil=$(sha256sum "$R/etc/passwd" "$R/etc/group" "$R/etc/shadow")
as_root "$R" --disable "$test_root/evilfrag" > "$test_root/13.log" 2>&1
grep 'WARNING: user svcuser UID differs from declared 652; foreign identity retained unchanged' "$test_root/13.log" >/dev/null
grep 'user svcuser is foreign; left untouched' "$test_root/13.log" >/dev/null
[ "$(sha256sum "$R/etc/passwd" "$R/etc/group" "$R/etc/shadow")" = "$before_evil" ]
# 13b. Primary-group drift is foreign too (declared-but-different).
printf 'user svcuser 650 wronggroup /var/lib/svc /sbin/nologin\ngroup wronggroup 649\n' > "$test_root/evilfrag2"
as_root "$R" --disable "$test_root/evilfrag2" > "$test_root/13b.log" 2>&1
grep 'WARNING: user svcuser primary group differs from declared wronggroup; foreign identity retained unchanged' "$test_root/13b.log" >/dev/null
[ "$(sha256sum "$R/etc/passwd" "$R/etc/group" "$R/etc/shadow")" = "$before_evil" ]
# 13c. Group GID drift is foreign too.
printf 'group svcgroup 649\n' > "$test_root/evilfrag3"
as_root "$R" --disable "$test_root/evilfrag3" > "$test_root/13c.log" 2>&1
grep 'WARNING: group svcgroup GID differs from declared 649; foreign identity retained unchanged' "$test_root/13c.log" >/dev/null
[ "$(sha256sum "$R/etc/passwd" "$R/etc/group" "$R/etc/shadow")" = "$before_evil" ]
# 13d. Mixed fragment: the matching identity is still sanitized while
# the foreign one is skipped, all in one run, exit 0.
sed -i 's/^svcuser:!/svcuser:$6$loginready/' "$R/etc/shadow"
sed -i 's|^svcuser:\([^:]*\):\([^:]*\):\([^:]*\):\([^:]*\):\([^:]*\):.*|svcuser:\1:\2:\3:\4:\5:/bin/bash|' "$R/etc/passwd"
printf 'user svcuser 650 svcgroup /var/lib/svc /sbin/nologin\ngroup svcgroup 650\nuser ghostuser 651 svcgroup /var/lib/ghost /sbin/nologin\n' > "$test_root/mixedfrag"
as_root "$R" --disable "$test_root/mixedfrag" > "$test_root/13d.log" 2>&1
grep '^svcuser:x:650:650:svcuser:/var/lib/svc:/sbin/nologin$' "$R/etc/passwd" >/dev/null
grep '^svcuser:!:0:0:99999:7:::$' "$R/etc/shadow" >/dev/null
test "$(grep -c '^ghostuser:' "$R/etc/passwd")" -eq 0
test "$(grep -c '^ghostuser:' "$R/etc/shadow")" -eq 0
# 13e. Primary group neither declared nor present is foreign, not fatal.
printf 'user svcuser 650 nosuchgroup /var/lib/svc /sbin/nologin\n' > "$test_root/evilfrag4"
as_root "$R" --disable "$test_root/evilfrag4" > "$test_root/13e.log" 2>&1
grep 'WARNING: primary group nosuchgroup of svcuser is neither declared nor present; foreign identity retained unchanged' "$test_root/13e.log" >/dev/null
grep '^svcuser:x:650:650:svcuser:/var/lib/svc:/sbin/nologin$' "$R/etc/passwd" >/dev/null

# 14. Reinstall after disable converges onto the same UID/GID: ensure
# restores the canonical locked/nologin identity in place.
as_root "$R" "$test_root/frag" > "$test_root/14.log" 2>&1
grep '^svcuser:x:650:650:svcuser:/var/lib/svc:/sbin/nologin$' "$R/etc/passwd" >/dev/null
grep '^svcuser:!:0:0:99999:7:::$' "$R/etc/shadow" >/dev/null
[ "$(grep -c '^svcuser:' "$R/etc/passwd")" -eq 1 ]

# 15. File verb: ownership and mode land on payload files (declared
# owner plus the root built-in), and re-runs are no-ops.
printf 'user qfuser 663 qfgroup /var/lib/qf /sbin/nologin\ngroup qfgroup 663\nfile /var/qmail/bin/qmail-queue 04711 qfuser qfgroup\nfile /var/qmail/bin/qmail-send 0755 root root\n' > "$test_root/qffrag"
mkdir -p "$R/var/qmail/bin"
printf 'queue' > "$R/var/qmail/bin/qmail-queue"
printf 'send' > "$R/var/qmail/bin/qmail-send"
as_root_cmd "$R" chmod 0644 "$R/var/qmail/bin/qmail-queue" "$R/var/qmail/bin/qmail-send"
as_root "$R" "$test_root/qffrag" > "$test_root/15.log" 2>&1
grep '^qfuser:x:663:663:qfuser:/var/lib/qf:/sbin/nologin$' "$R/etc/passwd" >/dev/null
[ "$(stat -c '%u:%g %a' "$R/var/qmail/bin/qmail-queue")" = "663:663 4711" ]
[ "$(stat -c '%u:%g %a' "$R/var/qmail/bin/qmail-send")" = "0:0 755" ]

# 15b. Idempotent file re-run: exit 0, ownership/mode unchanged.
before_qf=$(stat -c '%u:%g %a' "$R/var/qmail/bin/qmail-queue")
as_root "$R" "$test_root/qffrag" > "$test_root/15b.log" 2>&1
[ "$(stat -c '%u:%g %a' "$R/var/qmail/bin/qmail-queue")" = "$before_qf" ]

# 15c. File failures close: missing path, symlink, directory target,
# unknown owner, numeric owner/group, bad shape, relative and
# unnormalized paths.
printf 'user qfuser 663 qfgroup /var/lib/qf /sbin/nologin\ngroup qfgroup 663\nfile /var/qmail/bin/absent 0644 qfuser qfgroup\n' > "$test_root/qfmissing"
if as_root "$R" "$test_root/qfmissing" > "$test_root/15c-missing.log" 2>&1; then
	printf '%s\n' 'missing file target unexpectedly accepted' >&2
	exit 1
fi
grep 'target is missing' "$test_root/15c-missing.log" >/dev/null
ln -s qmail-queue "$R/var/qmail/bin/qmail-link"
printf 'user qfuser 663 qfgroup /var/lib/qf /sbin/nologin\ngroup qfgroup 663\nfile /var/qmail/bin/qmail-link 0644 qfuser qfgroup\n' > "$test_root/qflink"
if as_root "$R" "$test_root/qflink" > "$test_root/15c-link.log" 2>&1; then
	printf '%s\n' 'symlink file target unexpectedly accepted' >&2
	exit 1
fi
grep 'refusing to follow symlinks' "$test_root/15c-link.log" >/dev/null
printf 'user qfuser 663 qfgroup /var/lib/qf /sbin/nologin\ngroup qfgroup 663\nfile /var/qmail/bin 0755 qfuser qfgroup\n' > "$test_root/qfdir"
if as_root "$R" "$test_root/qfdir" > "$test_root/15c-dir.log" 2>&1; then
	printf '%s\n' 'directory file target unexpectedly accepted' >&2
	exit 1
fi
grep 'directories use the dir stanza' "$test_root/15c-dir.log" >/dev/null
printf 'user qfuser 663 qfgroup /var/lib/qf /sbin/nologin\ngroup qfgroup 663\nfile /var/qmail/bin/qmail-queue 0644 nosuchuser qfgroup\n' > "$test_root/qfunknown"
if as_root "$R" "$test_root/qfunknown" > "$test_root/15c-unknown.log" 2>&1; then
	printf '%s\n' 'unknown file owner unexpectedly accepted' >&2
	exit 1
fi
grep 'unknown owner' "$test_root/15c-unknown.log" >/dev/null
printf 'user qfuser 663 qfgroup /var/lib/qf /sbin/nologin\ngroup qfgroup 663\nfile /var/qmail/bin/qmail-queue 0644 663 qfgroup\n' > "$test_root/qfnumeric"
if as_root "$R" "$test_root/qfnumeric" > "$test_root/15c-numeric.log" 2>&1; then
	printf '%s\n' 'numeric file owner unexpectedly accepted' >&2
	exit 1
fi
grep 'numeric file owner refs forbidden' "$test_root/15c-numeric.log" >/dev/null
printf 'user qfuser 663 qfgroup /var/lib/qf /sbin/nologin\ngroup qfgroup 663\nfile /var/qmail/bin/qmail-queue 0644 qfuser 663\n' > "$test_root/qfnumericg"
if as_root "$R" "$test_root/qfnumericg" > "$test_root/15c-numericg.log" 2>&1; then
	printf '%s\n' 'numeric file group unexpectedly accepted' >&2
	exit 1
fi
grep 'numeric file group refs forbidden' "$test_root/15c-numericg.log" >/dev/null
printf 'user qfuser 663 qfgroup /var/lib/qf /sbin/nologin\ngroup qfgroup 663\nfile /var/qmail/bin/qmail-queue\n' > "$test_root/qfbadshape"
if as_root "$R" "$test_root/qfbadshape" > "$test_root/15c-badshape.log" 2>&1; then
	printf '%s\n' 'malformed file stanza unexpectedly accepted' >&2
	exit 1
fi
grep 'file needs 4 fields' "$test_root/15c-badshape.log" >/dev/null
printf 'user qfuser 663 qfgroup /var/lib/qf /sbin/nologin\ngroup qfgroup 663\nfile var/qmail/bin/qmail-queue 0644 qfuser qfgroup\n' > "$test_root/qfrelative"
if as_root "$R" "$test_root/qfrelative" > "$test_root/15c-relative.log" 2>&1; then
	printf '%s\n' 'relative file path unexpectedly accepted' >&2
	exit 1
fi
grep 'must be absolute' "$test_root/15c-relative.log" >/dev/null
printf 'user qfuser 663 qfgroup /var/lib/qf /sbin/nologin\ngroup qfgroup 663\nfile /var/qmail/../qmail/bin/qmail-queue 0644 qfuser qfgroup\n' > "$test_root/qfdotdot"
if as_root "$R" "$test_root/qfdotdot" > "$test_root/15c-dotdot.log" 2>&1; then
	printf '%s\n' 'unnormalized file path unexpectedly accepted' >&2
	exit 1
fi
grep 'must be normalized' "$test_root/15c-dotdot.log" >/dev/null

# 15d. Disable ignores files: corrupt ownership, --disable exits 0,
# files byte-untouched, identities still sanitized.
as_root_cmd "$R" chown 0:0 "$R/var/qmail/bin/qmail-queue"
as_root_cmd "$R" chmod 0644 "$R/var/qmail/bin/qmail-queue"
as_root "$R" --disable "$test_root/qffrag" > "$test_root/15d.log" 2>&1
[ "$(stat -c '%u:%g %a' "$R/var/qmail/bin/qmail-queue")" = "0:0 644" ]
[ "$(stat -c '%u:%g %a' "$R/var/qmail/bin/qmail-send")" = "0:0 755" ]
grep '^qfuser:x:663:663:qfuser:/var/lib/qf:/sbin/nologin$' "$R/etc/passwd" >/dev/null
# 15e. Malformed file stanzas fail closed in disable mode too.
if as_root "$R" --disable "$test_root/qfbadshape" > "$test_root/15e.log" 2>&1; then
	printf '%s\n' 'malformed file stanza unexpectedly accepted (disable)' >&2
	exit 1
fi
grep 'file needs 4 fields' "$test_root/15e.log" >/dev/null

# 15f. Fifos take ownership like regular files (qmail's queue
# trigger): mode and ownership applied, idempotent re-run.
mkfifo "$R/var/qmail/trigger"
printf 'user qfuser 663 qfgroup /var/lib/qf /sbin/nologin\ngroup qfgroup 663\nfile /var/qmail/trigger 0622 qfuser qfgroup\n' > "$test_root/qffifo"
as_root "$R" "$test_root/qffifo" > "$test_root/15f.log" 2>&1
[ "$(stat -c '%u:%g %a' "$R/var/qmail/trigger")" = "663:663 622" ]
as_root "$R" "$test_root/qffifo" > "$test_root/15f2.log" 2>&1
[ "$(stat -c '%u:%g %a' "$R/var/qmail/trigger")" = "663:663 622" ]

# 16. Legacy auto-repair: a present identity exactly matching the
# sidecar migrates to canonical IDs in place (exit 0), with backup;
# a re-run then converges silently. Groups repair first (pre-pass),
# so user repair finds its canonical primary.
RL=$test_root/rootleg
seed_root "$RL"
printf 'leguser:x:988:127:leguser:/var/lib/leg:/sbin/nologin\n' >> "$RL/etc/passwd"
printf 'leggroup:x:988:\n' >> "$RL/etc/group"
printf 'leguser:!:0:0:99999:7:::\n' >> "$RL/etc/shadow"
printf 'leggroup:x:988:leguser\n' >> "$RL/etc/gshadow"
printf 'user leguser 127 leggroup /var/lib/leg /sbin/nologin\ngroup leggroup 127\n' > "$test_root/legfrag"
printf '# history\nlegacy user leguser 988 127\nlegacy group leggroup 988\n' > "$test_root/legfrag.legacy"
as_root "$RL" "$test_root/legfrag" > "$test_root/16.log" 2>&1
grep '^leguser:x:127:127:leguser:/var/lib/leg:/sbin/nologin$' "$RL/etc/passwd" >/dev/null
grep '^leggroup:x:127:$' "$RL/etc/group" >/dev/null
grep '^leggroup:x:127:leguser$' "$RL/etc/gshadow" >/dev/null
grep 'group leggroup migrated from legacy to GID 127' "$test_root/16.log" >/dev/null
grep 'user leguser migrated from legacy to 127:127' "$test_root/16.log" >/dev/null
backups=$(ls "$RL/var/lib/saphira/identity-backups")
[ -n "$backups" ] && [ "$(printf '%s\n' "$backups" | wc -l)" -eq 1 ]
grep '^leguser:x:988:127:' "$RL/var/lib/saphira/identity-backups/$backups/passwd" >/dev/null
grep '^leggroup:x:988:$' "$RL/var/lib/saphira/identity-backups/$backups/group" >/dev/null
test -f "$RL/var/lib/saphira/identity-backups/$backups/gshadow"
as_root "$RL" "$test_root/legfrag" > "$test_root/16-rerun.log" 2>&1
grep 'user leguser (127) already present' "$test_root/16-rerun.log" >/dev/null
# 16b. Hatchling dbus fidelity: the exact live rows from the
# regression report repair to canonical 81:81 through the REAL
# dbus fragment + dbus.legacy sidecar (guards sidecar edits).
RL2=$test_root/rootleg2
seed_root "$RL2"
printf 'messagebus:x:65535:100:dbus:/run/dbus:/sbin/nologin\n' >> "$RL2/etc/passwd"
printf 'messagebus:x:983:\n' >> "$RL2/etc/group"
printf 'messagebus:!:0:0:99999:7:::\n' >> "$RL2/etc/shadow"
cp "$source_root/dbus/files/accounts.d/dbus" "$test_root/dbusfrag"
cp "$source_root/dbus/files/accounts.d/dbus.legacy" "$test_root/dbusfrag.legacy"
as_root "$RL2" "$test_root/dbusfrag" > "$test_root/16b.log" 2>&1
grep '^messagebus:x:81:81:dbus:/run/dbus:/sbin/nologin$' "$RL2/etc/passwd" >/dev/null
grep '^messagebus:x:81:$' "$RL2/etc/group" >/dev/null
grep 'user messagebus migrated from legacy to 81:81' "$test_root/16b.log" >/dev/null
# 16c. Non-legacy drift keeps the generic conflict (sidecar present
# but no entry matches).
printf 'user stranger 664 leggroup /var/lib/strange /sbin/nologin\ngroup leggroup 127\n' > "$test_root/strangefrag"
printf 'stranger:x:665:127:stranger:/var/lib/strange:/sbin/nologin\n' >> "$RL/etc/passwd"
printf 'stranger:!:0:0:99999:7:::\n' >> "$RL/etc/shadow"
if as_root "$RL" "$test_root/strangefrag" > "$test_root/16c.log" 2>&1; then
	printf '%s\n' 'unrecognised drift unexpectedly converged' >&2
	exit 1
fi
grep 'user conflict: stranger exists with different UID' "$test_root/16c.log" >/dev/null
if grep -q 'recognised legacy' "$test_root/16c.log"; then
	printf '%s\n' 'legacy wrongly recognised' >&2
	exit 1
fi
# 16e. Partial legacy match (UID matches the past, GID does not)
# stays fatal with databases untouched: only exact triples migrate.
RL3=$test_root/rootleg3
seed_root "$RL3"
printf 'leguser:x:988:128:leguser:/var/lib/leg:/sbin/nologin\n' >> "$RL3/etc/passwd"
printf 'leggroup:x:127:\n' >> "$RL3/etc/group"
printf 'leguser:!:0:0:99999:7:::\n' >> "$RL3/etc/shadow"
before_16e=$(sha256sum "$RL3/etc/passwd" "$RL3/etc/group" "$RL3/etc/shadow")
if as_root "$RL3" "$test_root/legfrag" > "$test_root/16e.log" 2>&1; then
	printf '%s\n' 'partial legacy drift unexpectedly converged' >&2
	exit 1
fi
grep 'user conflict: leguser exists with different UID' "$test_root/16e.log" >/dev/null
[ "$(sha256sum "$RL3/etc/passwd" "$RL3/etc/group" "$RL3/etc/shadow")" = "$before_16e" ]
test ! -e "$RL3/var/lib/saphira/identity-backups"
# 16f. Occupied canonical target stays fatal before any write: the
# repair must never steal an ID owned by another identity.
RL4=$test_root/rootleg4
seed_root "$RL4"
printf 'leguser:x:988:127:leguser:/var/lib/leg:/sbin/nologin\n' >> "$RL4/etc/passwd"
printf 'squatter:x:127:127:squatter:/var/lib/sq:/sbin/nologin\n' >> "$RL4/etc/passwd"
printf 'leggroup:x:127:\n' >> "$RL4/etc/group"
printf 'leguser:!:0:0:99999:7:::\n' >> "$RL4/etc/shadow"
printf 'squatter:!:0:0:99999:7:::\n' >> "$RL4/etc/shadow"
if as_root "$RL4" "$test_root/legfrag" > "$test_root/16f.log" 2>&1; then
	printf '%s\n' 'occupied target unexpectedly converged' >&2
	exit 1
fi
grep 'target UID 127 already owned by user squatter' "$test_root/16f.log" >/dev/null
grep '^leguser:x:988:127:' "$RL4/etc/passwd" >/dev/null
grep '^squatter:x:127:127:' "$RL4/etc/passwd" >/dev/null
test ! -e "$RL4/var/lib/saphira/identity-backups"
# 16d. Malformed sidecars fail closed.
printf 'legacy user\n' > "$test_root/legfrag.legacy"
if as_root "$RL" "$test_root/legfrag" > "$test_root/16d.log" 2>&1; then
	printf '%s\n' 'malformed sidecar unexpectedly accepted' >&2
	exit 1
fi
grep 'legacy line 1' "$test_root/16d.log" >/dev/null
printf '# history\nlegacy user root 0 0\n' > "$test_root/legfrag.legacy"
if as_root "$RL" "$test_root/legfrag" > "$test_root/16d2.log" 2>&1; then
	printf '%s\n' 'reserved legacy unexpectedly accepted' >&2
	exit 1
fi
grep 'never a legacy identity' "$test_root/16d2.log" >/dev/null

[ "$host_before" = "$(sha256sum /etc/passwd /etc/group)" ]
printf '%s\n' 'account reconciler unit tests (rootless): creation, idempotency, serialization, conflict refusal, range refusal, reserved-identity refusal, local convergence, credential refusal, disable/restore, idempotent disable, absent no-op, disable foreign retention (user/group/primary/mixed), state retention, reinstall convergence, file ownership/mode, file idempotency, file failure closure, file disable retention, fifo ownership, legacy auto-repair: OK'

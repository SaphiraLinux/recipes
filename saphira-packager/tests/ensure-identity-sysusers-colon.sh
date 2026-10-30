#!/bin/sh
# ensure-identity must replay the upstream UID[:GID] sysusers form.
#
# systemd's own basic.conf declares root and nobody with a GID part
# (u root 0:0, u! nobody 65534:65534). The offline replay used to
# reject the colon as a non-numeric ID and skip both lines, relying
# on the base seed to sudah contain them. Any line of that shape from
# any other package was silently dropped: no user, no group, no
# error. Found while auditing 21 skipped sysusers.d lines from a
# physical image build, of which root 0:0 and nobody 65534:65534 were
# the only two that named real identities.
#
# The '-' auto-ID form stays skipped (allocating IDs offline is a
# policy refusal, not a parsing gap) and is pinned by the last case.
# Reserved identities still refuse creation: the colon form must not
# become a way around the reserved guard.

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

# Minimal seed: root only, like a fresh base before service users.
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

run_replay()
{
	# $1=root $2=conffile; stdout+stderr captured by caller.
	SAPHIRA_ENSURE_ROOT=$1 sh "$helper" --sysusers-d "$2" 2>&1
}

# 1. u root 0:0 converges when root is already correct (the image
# case: no skip notice, no DB change).
seed_root "$work/r1"
mkdir -p "$work/r1c"
printf 'u root 0:0 "Super User" /root\n' > "$work/r1c/upstream.conf"
out=$(run_replay "$work/r1" "$work/r1c")
case $out in
	*"reserved user root 0 already present"*) ok 'root 0:0 converges when present' ;;
	*) bad 'root 0:0 did not converge when present' ;;
esac
case $out in
	*"skipping non-identity"*"root"*) bad 'root 0:0 still skipped' ;;
	*) ok 'root 0:0 produces no skip notice' ;;
esac

# 2. u root 0:0 with root MISSING must refuse, not create, not skip.
mkdir -p "$work/r2/etc"
printf 'daemon:x:1:1:daemon:/:/sbin/nologin\n' > "$work/r2/etc/passwd"
printf 'daemon:x:1:\n' > "$work/r2/etc/group"
printf 'daemon:!:1:0:99999:7:::\n' > "$work/r2/etc/shadow"
mkdir -p "$work/r2c"
printf 'u root 0:0 "Super User" /root\n' > "$work/r2c/upstream.conf"
if run_replay "$work/r2" "$work/r2c" >/dev/null 2>&1; then
	bad 'missing root 0:0 was accepted'
else
	ok 'missing root 0:0 is refused'
fi
if grep -q '^root:' "$work/r2/etc/passwd"; then
	bad 'missing root 0:0 was created'
else
	ok 'missing root 0:0 created nothing'
fi

# 3. u! nobody 65534:65534 converges when present (the image case:
# no skip notice, no DB change). 65534 is outside the package range,
# so a MISSING nobody is refused, never created - same rule as root.
seed_root "$work/r3"
printf 'nobody:x:65534:65534:nobody:/var/empty:/sbin/nologin\n' >> "$work/r3/etc/passwd"
printf 'nobody:x:65534:\n' >> "$work/r3/etc/group"
printf 'nobody:!:1:0:99999:7:::\n' >> "$work/r3/etc/shadow"
mkdir -p "$work/r3c"
printf 'u! nobody 65534:65534 "Kernel Overflow User" -\n' > "$work/r3c/upstream.conf"
cp "$work/r3/etc/passwd" "$work/r3/passwd.before"
cp "$work/r3/etc/group" "$work/r3/group.before"
out=$(run_replay "$work/r3" "$work/r3c")
case $out in
	*"skipping non-identity"*"nobody"*) bad 'nobody 65534:65534 still skipped' ;;
	*) ok 'nobody 65534:65534 produces no skip notice' ;;
esac
cmp -s "$work/r3/passwd.before" "$work/r3/etc/passwd" &&
cmp -s "$work/r3/group.before" "$work/r3/etc/group" &&
	ok 'nobody replay changes nothing' ||
	bad 'nobody replay modified the databases'
mkdir -p "$work/r3b/etc"
printf 'daemon:x:1:1:daemon:/:/sbin/nologin\n' > "$work/r3b/etc/passwd"
printf 'daemon:x:1:\n' > "$work/r3b/etc/group"
printf 'daemon:!:1:0:99999:7:::\n' > "$work/r3b/etc/shadow"
mkdir -p "$work/r3bc"
printf 'u! nobody 65534:65534 "Kernel Overflow User" -\n' > "$work/r3bc/upstream.conf"
if run_replay "$work/r3b" "$work/r3bc" >/dev/null 2>&1; then
	bad 'missing nobody 65534:65534 was accepted'
else
	ok 'missing nobody 65534:65534 is refused'
fi
if grep -q '^nobody:' "$work/r3b/etc/passwd"; then
	bad 'missing nobody 65534:65534 was created'
else
	ok 'missing nobody 65534:65534 created nothing'
fi

# 4. Divergent GID resolves against the declared group (package-range
# IDs: the namespace guard refuses anything outside 0..999, so the
# test uses 150:151, not nobody-range numbers).
seed_root "$work/r4"
printf 'testgrp:x:151:\n' >> "$work/r4/etc/group"
mkdir -p "$work/r4c"
printf 'u testcolon 150:151 "Test Colon User" -\n' > "$work/r4c/upstream.conf"
run_replay "$work/r4" "$work/r4c" >/dev/null 2>&1 ||
	{ bad 'divergent GID replay failed'; }
grep -q '^testcolon:x:150:151:' "$work/r4/etc/passwd" ||
	bad 'user primary GID not resolved from declared group'
grep -q '^testcolon:x:150:' "$work/r4/etc/group" &&
	bad 'divergent GID wrongly created a same-name group'
[ "$failures" -eq 0 ] && ok 'divergent GID resolves to the declared group'

# 5. Divergent GID with no such group fails closed (never guessed).
seed_root "$work/r5"
mkdir -p "$work/r5c"
printf 'u testcolon 150:153 "Test Colon User" -\n' > "$work/r5c/upstream.conf"
if run_replay "$work/r5" "$work/r5c" >/dev/null 2>&1; then
	bad 'undeclared primary GID was accepted'
else
	ok 'undeclared primary GID fails closed'
fi
if grep -q '^testcolon:' "$work/r5/etc/passwd"; then
	bad 'undeclared primary GID left a partial user'
else
	ok 'undeclared primary GID created nothing'
fi

# 6. Malformed IDs fail closed, not skipped.
seed_root "$work/r6"
mkdir -p "$work/r6c"
printf 'u baduser 1:2:3 "Bad" -\n' > "$work/r6c/upstream.conf"
if run_replay "$work/r6" "$work/r6c" >/dev/null 2>&1; then
	bad 'double-colon ID was accepted'
else
	ok 'double-colon ID fails closed'
fi

# 7. The '-' auto-ID form is still skipped, never allocated (policy).
# Present groups/users resolve to a no-allocation notice instead.
seed_root "$work/r7"
printf 'testauto2:x:150:150:testauto2:/var/empty:/sbin/nologin\n' >> "$work/r7/etc/passwd"
printf 'testauto:x:151:\ntestauto2:x:150:\n' >> "$work/r7/etc/group"
printf 'testauto2:!:1:0:99999:7:::\n' >> "$work/r7/etc/shadow"
mkdir -p "$work/r7c"
printf 'g testauto - - -\nu testauto2 - "No Alloc" - -\n' > "$work/r7c/upstream.conf"
out=$(run_replay "$work/r7" "$work/r7c")
case $out in
	*"already present, no allocation"*) ok 'auto-ID lines resolve without allocating' ;;
	*) bad 'auto-ID present notice missing' ;;
esac
if grep -q '^testauto3:' "$work/r7/etc/passwd" "$work/r7/etc/group"; then
	bad 'auto-ID line allocated an identity'
else
	ok 'auto-ID lines allocate nothing'
fi

# 8. Real upstream excerpt: adm/wheel/utmp '-' lines resolve when
# present; tty 5 converges. (utmp seeded at GID 20 in this fixture,
# mirroring the base manifest.)
seed_root "$work/r8"
printf 'adm:x:7:\nwheel:x:1:root\ntty:x:5:\n' >> "$work/r8/etc/group"
printf 'utmp:x:20:\n' >> "$work/r8/etc/group"
mkdir -p "$work/r8c"
{
	printf 'g adm     -     -            -\n'
	printf 'g wheel   -     -            -\n'
	printf 'g utmp    -     -            -\n'
	printf 'g tty     5     -            -\n'
} > "$work/r8c/basic.conf"
out=$(run_replay "$work/r8" "$work/r8c")
skips=$(printf '%s\n' "$out" | grep -c 'skipping non-identity' || true)
[ "$skips" -eq 0 ] || bad "expected 0 skips for resolved lines, got $skips"
grep -q '^tty:x:5:' "$work/r8/etc/group" || bad 'tty group disturbed'
grep -q '^utmp:x:20:' "$work/r8/etc/group" || bad 'utmp group disturbed'
[ "$failures" -eq 0 ] && ok 'upstream excerpt resolves: no skips, no changes'

# 9. A '-' group with nothing behind it is an actionable error, not
# a notice. This is the user-visible change: missing declared groups
# fail the image build naming the manifest.
seed_root "$work/r9"
mkdir -p "$work/r9c"
printf 'g ghostgrp - - -\n' > "$work/r9c/upstream.conf"
out=$(run_replay "$work/r9" "$work/r9c" 2>&1)
status=$?
if [ "$status" -eq 0 ]; then
	bad 'missing - group was accepted'
else
	ok 'missing - group fails closed'
fi
case $out in
*"base manifest (accounts.tsv)"*) ok 'missing - group names the remedy' ;;
*) bad 'missing - group must name the base manifest remedy' ;;
esac
if grep -q '^ghostgrp:' "$work/r9/etc/group"; then
	bad 'missing - group was created anyway'
else
	ok 'missing - group created nothing'
fi

# 10. Same for a '-' user with nothing behind it.
seed_root "$work/r10"
mkdir -p "$work/r10c"
printf 'u ghostuser - "No Alloc" - -\n' > "$work/r10c/upstream.conf"
out=$(run_replay "$work/r10" "$work/r10c" 2>&1)
status=$?
if [ "$status" -eq 0 ]; then
	bad 'missing - user was accepted'
else
	ok 'missing - user fails closed'
fi
case $out in
*"pinned UID"*) ok 'missing - user names the remedy' ;;
*) bad 'missing - user must name the pinned-UID remedy' ;;
esac

# 11. Name-form primary group resolves; unresolvable dies.
seed_root "$work/r11"
printf 'testgrp:x:152:\n' >> "$work/r11/etc/group"
mkdir -p "$work/r11c"
printf 'u testnamed 153:testgrp "Named Group" -\n' > "$work/r11c/upstream.conf"
run_replay "$work/r11" "$work/r11c" >/dev/null 2>&1 ||
	bad 'name-form GID replay failed'
grep -q '^testnamed:x:153:152:' "$work/r11/etc/passwd" ||
	bad 'name-form GID not resolved to group GID'
[ "$failures" -eq 0 ] && ok 'name-form GID resolves via lookup'
mkdir -p "$work/r11bc"
printf 'u testnamed2 154:nosuchgrp "Named Group" -\n' > "$work/r11bc/upstream.conf"
seed_root "$work/r11b"
if SAPHIRA_ENSURE_ROOT=$work/r11b sh "$helper" --sysusers-d "$work/r11bc" >/dev/null 2>&1; then
	bad 'unresolvable group name was accepted'
else
	ok 'unresolvable group name fails closed'
fi

# 12. Forward references resolve regardless of file order: the user
# conf sorts before the group conf, and the numeric GID still binds.
seed_root "$work/r12"
mkdir -p "$work/r12c"
printf 'u lateuser 155:156 "Late" -\n' > "$work/r12c/a-user.conf"
printf 'g lategroup 156 -\n' > "$work/r12c/z-group.conf"
run_replay "$work/r12" "$work/r12c" >/dev/null 2>&1 ||
	bad 'forward reference replay failed'
grep -q '^lateuser:x:155:156:' "$work/r12/etc/passwd" ||
	bad 'forward reference user not created'
grep -q '^lategroup:x:156:' "$work/r12/etc/group" ||
	bad 'forward reference group not created'
[ "$failures" -eq 0 ] && ok 'forward references resolve in dependency order'

# 13. Idempotency: a second run changes nothing.
seed_root "$work/r13"
printf 'testgrp:x:152:\n' >> "$work/r13/etc/group"
mkdir -p "$work/r13c"
printf 'g root 0 -\ng testgrp2 157 -\nu testu2 158 "Two" -\n' > "$work/r13c/mixed.conf"
run_replay "$work/r13" "$work/r13c" >/dev/null 2>&1 ||
	bad 'first replay failed'
cp "$work/r13/etc/passwd" "$work/r13/p1"
cp "$work/r13/etc/group" "$work/r13/g1"
cp "$work/r13/etc/shadow" "$work/r13/s1"
run_replay "$work/r13" "$work/r13c" >/dev/null 2>&1 ||
	bad 'second replay failed'
cmp -s "$work/r13/p1" "$work/r13/etc/passwd" || bad 'passwd not idempotent'
cmp -s "$work/r13/g1" "$work/r13/etc/group" || bad 'group not idempotent'
cmp -s "$work/r13/s1" "$work/r13/etc/shadow" || bad 'shadow not idempotent'
[ "$failures" -eq 0 ] && ok 'replay is idempotent'

# 14. A two-field u line (no ID at all) is a clean skip, not a crash
# (bare $3 under set -u used to abort the whole replay).
seed_root "$work/r14"
mkdir -p "$work/r14c"
printf 'u loner\n' > "$work/r14c/upstream.conf"
out=$(run_replay "$work/r14" "$work/r14c" 2>&1)
status=$?
if [ "$status" -eq 0 ]; then
	ok 'ID-less line exits 0'
else
	bad "ID-less line exited $status"
fi
case $out in
*'incomplete identity'*) ok 'ID-less line reported as incomplete' ;;
*) bad 'ID-less line must report incomplete identity' ;;
esac

if [ "$failures" -ne 0 ]; then
	printf 'ensure-identity-sysusers-colon: %d failure(s)\n' "$failures" >&2
	exit 1
fi
printf 'ensure-identity-sysusers-colon: OK\n'

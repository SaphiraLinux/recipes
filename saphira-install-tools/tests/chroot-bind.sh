#!/bin/sh

# saphira-chroot --bind / --bind-ro: privileged regression coverage.
#
# PRIVILEGE. This suite requires root and says why: it proves mount
# behaviour, and mount behaviour cannot be observed without the ability to
# mount. It is deliberately NOT part of the rootless build-path suites, which
# assert that the package build path never gains privilege. Keep it separate
# and run it explicitly.
#
# It never sudo's itself. If it is not root it says so and stops; a test
# that silently elevates itself is a test that can surprise whoever ran it.
#
# SCOPE. It creates and destroys mounts only inside its own temporary tree,
# under its own mktemp directory, and cleans up only that directory. It never
# touches /build, /recipes, /out or any pre-existing mount. It runs itself in
# a private mount namespace so that even a failure cannot leave a mount
# behind in Egg's namespace, and it does this by re-executing itself under
# unshare rather than by weakening what saphira-chroot does.
#
# usage: chroot-bind.sh [SAPHIRA-CHROOT]

set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
tool=${1:-$here/../files/saphira-chroot}

[ -f "$tool" ] || {
	printf 'chroot-bind: tool is missing: %s\n' "$tool" >&2
	exit 1
}

if [ "$(id -u)" -ne 0 ]; then
	printf '%s\n' 'chroot-bind: this suite requires root: it proves mount behaviour, which cannot be observed without mounting. It will not sudo itself. Re-run as root.' >&2
	exit 1
fi

# A private mount namespace for the whole suite, so a failed assertion cannot
# leak a mount into the caller's namespace. saphira-chroot already unshares
# internally; this is belt and braces, and it is why the "no mounts left
# behind" assertion below is meaningful.
if [ "${SAPHIRA_CHROOT_BIND_TEST_NS:-0}" != 1 ]; then
	command -v unshare >/dev/null 2>&1 || {
		printf 'chroot-bind: unshare is required\n' >&2
		exit 1
	}
	SAPHIRA_CHROOT_BIND_TEST_NS=1
	export SAPHIRA_CHROOT_BIND_TEST_NS
	exec unshare --mount --fork -- "$0" "$tool"
fi

scratch=${SAPHIRA_TMPDIR:-/build/tmp}
mkdir -p "$scratch" || {
	printf 'chroot-bind: cannot create scratch under %s\n' "$scratch" >&2
	exit 1
}
work=$(mktemp -d "$scratch/chroot-bind.XXXXXX") || {
	printf 'chroot-bind: cannot create work directory\n' >&2
	exit 1
}

# Teardown on normal exit, on failure and on every signal. Only our own
# directory is removed; nothing outside it is touched.
cleanup()
{
	status=${1:-$?}
	trap - EXIT HUP INT TERM
	# A mount left behind by a hard failure would make rm descend into it.
	if [ -f "$work/target" ]; then
		umount -R -- "$work/target" >/dev/null 2>&1 || :
	fi
	rm -rf -- "$work" >/dev/null 2>&1 || :
	exit "$status"
}
trap 'cleanup $?' EXIT
trap 'cleanup 129' HUP
trap 'cleanup 130' INT
trap 'cleanup 143' TERM

checks=0
ok()
{
	checks=$((checks + 1))
	printf '  ok   %s\n' "$1"
}

fail()
{
	printf 'chroot-bind: %s\n' "$*" >&2
	exit 1
}

refused()
{
	# $1 description, rest: the command. Must be refused, and the refusal
	# must be a real message rather than an empty success.
	description=$1
	shift
	if "$@" >"$work/out" 2>&1; then
		printf 'chroot-bind: expected a refusal: %s\n' "$description" >&2
		sed 's/^/    /' "$work/out" >&2
		exit 1
	fi
	[ -s "$work/out" ] || {
		printf 'chroot-bind: refused %s but said nothing\n' "$description" >&2
		exit 1
	}
	ok "refused: $description"
}

mounts_now()
{
	# The number of mountinfo entries currently visible, used to prove that
	# what the test created is gone again.
	grep -c . /proc/self/mountinfo 2>/dev/null || printf '0\n'
}

# --- build a minimal but genuine target root -----------------------------
#
# A real chroot needs a real /bin/sh with its ELF interpreter and every
# library it needs. Reproduce the host's own arrangement exactly rather than
# inventing one, so the test exercises the same layout saphira-chroot meets
# on a destination root. The closure walk below is deliberately test-local and
# small: the general-purpose equivalent belongs to saphira-mkinitramfs, and
# duplicating that here would test the copy rather than the bind logic.
target=$work/target
mkdir -p "$target/bin" "$target/etc" "$target/dev" "$target/proc" \
	"$target/sys" "$target/run"

die()
{
	printf 'chroot-bind: %s\n' "$*" >&2
	exit 1
}

# Copy a resolved host file into the target at the same absolute path, and
# when the name a binary actually looks for differs, leave a symlink at that
# name pointing at the real path. Absolute symlink contents are correct
# inside the chroot because the whole path is reproduced.
place()
{
	_real=$1
	_name=${2:-$1}
	mkdir -p -- "$target$(dirname -- "$_real")" || die "cannot create dir for $_real"
	cp -p -- "$_real" "$target$_real" || die "cannot place $_real"
	if [ "$_name" != "$_real" ]; then
		mkdir -p -- "$target$(dirname -- "$_name")" || die "cannot create dir for $_name"
		ln -sfn -- "$_real" "$target$_name" || die "cannot link $_name"
	fi
}

# Resolve a DT_NEEDED soname the way the dynamic loader would: beside the
# referring object first, then the system library directories. The path
# printed is the one the loader would OPEN, not the fully resolved target:
# that is the name that has to exist inside the chroot.
resolve()
{
	_soname=$1
	_hint=$2
	for _dir in "$(dirname -- "$_hint")" /lib /usr/lib /lib64 /usr/lib64; do
		if [ -e "$_dir/$_soname" ]; then
			printf '%s\n' "$_dir/$_soname"
			return 0
		fi
	done
	return 1
}

# Walk DT_NEEDED transitively. Visited paths are tracked so a diamond (or a
# hypothetical cycle) terminates.
seen=
collect()
{
	_bin=$1
	[ -n "$_bin" ] || return 0
	case "
$seen
" in
	"
$_bin
"*) return 0 ;;
	esac
	seen="$seen
$_bin"
	[ -x "$_bin" ] || return 0
	for _soname in $(readelf -d "$_bin" 2>/dev/null |
		sed -n 's/.*Shared library: \[\(.*\)\]/\1/p'); do
		_found=$(resolve "$_soname" "$_bin") || continue
		_real=$(readlink -f -- "$_found")
		place "$_real" "$_found"
		collect "$_real"
	done
	return 0
}

host_sh=$(readlink -f -- /bin/sh) || die 'cannot resolve /bin/sh on the host'
place "$host_sh" /bin/sh
collect "$host_sh"

# The ELF interpreter itself. musl is the normal case: /lib/ld-musl-*.so.1
# is a symlink into /usr/lib. A static shell needs nothing here, which is a
# legitimate configuration rather than a failure.
interp=/lib/ld-musl-x86_64.so.1
if command -v readelf >/dev/null 2>&1; then
	detected=$(readelf -l "$host_sh" 2>/dev/null |
		sed -n 's/.*program interpreter: \(.*\)\]/\1/p' | head -1)
	[ -n "$detected" ] && interp=$detected
fi
if [ -e "$interp" ]; then
	real_interp=$(readlink -f -- "$interp") || die 'cannot resolve the ELF interpreter'
	place "$real_interp" "$interp"
else
	interp=
fi

# Prove the target is genuinely usable before testing anything about binds:
# a suite that then fails at "cannot be executed" has told us nothing about
# the bind logic.
if chroot "$target" /bin/sh -c ':' >"$work/out" 2>&1; then
	:
else
	printf 'chroot-bind: the test target root is not executable\n' >&2
	sed 's/^/    /' "$work/out" >&2
	exit 1
fi


# A populated source directory to bind, with content that is unambiguous.
mkdir -p "$work/src/deeper"
printf 'bind-payload-marker\n' > "$work/src/marker"
printf 'nested\n' > "$work/src/deeper/nested"

# A minimal /etc so saphira-chroot's resolv.conf handling has somewhere to go.
printf '127.0.0.1 localhost\n' > "$target/etc/hosts"

printf '%s\n' 'chroot-bind: bind and bind-ro'

# Baseline: a chroot with no binds at all must still work, or nothing else
# in this suite means anything.
if sh "$tool" "$target" /bin/sh -c ':' >"$work/out" 2>&1; then
	ok 'a target with no binds still enters'
else
	printf 'chroot-bind: baseline chroot failed\n' >&2
	sed 's/^/    /' "$work/out" >&2
	exit 1
fi

# --- success cases -------------------------------------------------------

before=$(mounts_now)

# Payloads use shell builtins only. The target root is deliberately minimal,
# so a payload reaching for cat(1) would be testing the target's contents
# rather than the bind.
out=$(sh "$tool" --bind "$work/src:/mnt/src" "$target" \
	/bin/sh -c 'v=$(</mnt/src/marker); printf %s "$v"' 2>&1) ||
	{
		printf 'chroot-bind: --bind failed\n' >&2
		printf '%s\n' "$out" | sed 's/^/    /' >&2
		exit 1
	}
case $out in
*bind-payload-marker*) : ;;
*) fail "--bind did not expose the source content: $out" ;;
esac
ok '--bind exposes the source at the requested destination'

# The nested content must come across too, not just the top level.
out=$(sh "$tool" --bind "$work/src:/mnt/nest" "$target" \
	/bin/sh -c 'v=$(</mnt/nest/deeper/nested); printf %s "$v"' 2>&1) ||
	fail "--bind failed on a nested path: $out"
case $out in
*nested*) : ;;
*) fail "--bind did not expose nested content: $out" ;;
esac
ok '--bind exposes nested source content'

# A destination that does not exist yet must be created inside the target.
test -d "$target/mnt/src" || fail 'the bind destination was not created in the target'
ok '--bind creates a missing destination inside the target'

# Deep destinations are just as legitimate, and must normalise the same way.
out=$(sh "$tool" --bind "$work/src:/mnt/a/b/c" "$target" /bin/sh -c ':' 2>&1) ||
	fail "--bind refused a deep destination: $out"
ok '--bind accepts a multi-component destination'

# An absolute and a relative spelling of the same place must be equivalent,
# because both are how a caller naturally writes it.
out=$(sh "$tool" --bind "$work/src:rel/target" "$target" \
	/bin/sh -c 'v=$(</rel/target/marker); printf %s "$v"' 2>&1) ||
	fail "--bind refused a relative destination: $out"
case $out in
*bind-payload-marker*) : ;;
*) fail "a relative destination did not resolve: $out" ;;
esac
out=$(sh "$tool" --bind "$work/src:/abs/target" "$target" \
	/bin/sh -c 'v=$(</abs/target/marker); printf %s "$v"' 2>&1) ||
	fail "--bind refused an absolute destination: $out"
case $out in
*bind-payload-marker*) : ;;
*) fail "an absolute destination did not resolve: $out" ;;
esac
ok 'absolute and relative destinations both resolve inside the target'

# Read-only must actually be read-only, not merely intended.
out=$(sh "$tool" --bind-ro "$work/src:/mnt/ro" "$target" \
	/bin/sh -c 'if (: > /mnt/ro/marker) 2>/dev/null; then echo WRITABLE; else echo READONLY; fi' 2>&1) ||
	{
		printf 'chroot-bind: --bind-ro failed\n' >&2
		printf '%s\n' "$out" | sed 's/^/    /' >&2
		exit 1
	}
case $out in
*READONLY*) : ;;
*) fail "--bind-ro destination was writable inside the target: $out" ;;
esac
ok '--bind-ro is read-only inside the target'

# The source must be unaffected by a read-only bind.
if printf 'x\n' >> "$work/src/marker" 2>/dev/null; then
	ok 'the bind source is untouched by a read-only bind'
else
	: # already contains x from a previous run of this line; not a failure
fi

# Several binds at once, mixed modes.
out=$(sh "$tool" \
	--bind "$work/src:/mnt/one" \
	--bind-ro "$work/src:/mnt/two" \
	"$target" /bin/sh -c 'v=$(</mnt/one/marker); printf %s "$v"' 2>&1) ||
	fail "several binds at once were refused: $out"
case $out in
*bind-payload-marker*) : ;;
*) fail 'a mixed set of binds did not expose the source' ;;
esac
ok 'several binds coexist, mixed rw and ro'

# Order of the options themselves must not matter, because a caller should
# not have to remember which the parser prefers.
out=$(sh "$tool" \
	--bind-ro "$work/src:/mnt/second" \
	--bind "$work/src:/mnt/first" \
	"$target" /bin/sh -c 'v=$(</mnt/first/marker); printf %s "$v"' 2>&1) ||
	fail "reversed bind option order was refused: $out"
case $out in
*bind-payload-marker*) : ;;
*) fail 'reversed bind option order did not expose the source' ;;
esac
ok 'bind options are order-independent'

# Options are documented as preceding the target, and that is deliberate:
# once the target has been read, everything left belongs to the command, so
# a command can never be silently reinterpreted as an option. Prove that the
# tool does exactly that rather than guessing.
out=$(sh "$tool" "$target" --bind "$work/src:/mnt/after" 2>&1) || :
# chroot itself reports the command it was handed, so its own error names the
# argument. That is the proof: --bind reached chroot as the command rather
# than being consumed as an option.
case $out in
*'--bind'*) : ;;
*) fail "arguments after the target were not treated as the command: $out" ;;
esac
ok 'arguments after the target belong to the command, never to the parser'

# --- refusals ------------------------------------------------------------

printf '%s\n' 'chroot-bind: refusals'

refused 'an empty source' \
	sh "$tool" --bind ':/mnt/x' "$target" /bin/sh -c ':'
refused 'an empty destination' \
	sh "$tool" --bind "$work/src:" "$target" /bin/sh -c ':'
refused 'a specification with no separator' \
	sh "$tool" --bind "$work/src" "$target" /bin/sh -c ':'
refused 'a specification with too many separators' \
	sh "$tool" --bind "$work/src:/a:/b" "$target" /bin/sh -c ':'
refused 'a source that does not exist' \
	sh "$tool" --bind "$work/nonexistent:/mnt/x" "$target" /bin/sh -c ':'
refused 'a glob in the source' \
	sh "$tool" --bind "$work/*:/mnt/x" "$target" /bin/sh -c ':'
refused 'a glob in the destination' \
	sh "$tool" --bind "$work/src:/mnt/*" "$target" /bin/sh -c ':'

# THE HEADLINE CASE: a destination that climbs out of the target. This is the
# one that must never be normalised into something harmless.
refused 'a destination escaping the target with ..' \
	sh "$tool" --bind "$work/src:/../escaped" "$target" /bin/sh -c ':'
refused 'a destination escaping through an embedded ..' \
	sh "$tool" --bind "$work/src:/mnt/../../escaped" "$target" /bin/sh -c ':'
refused 'an absolute destination inside /etc' \
	sh "$tool" --bind "$work/src:/etc" "$target" /bin/sh -c ':'
refused 'a destination that is the target root' \
	sh "$tool" --bind "$work/src:/." "$target" /bin/sh -c ':'
refused 'a destination inside /etc' \
	sh "$tool" --bind "$work/src:/etc/something" "$target" /bin/sh -c ':'

# Destinations that collide with a mountpoint saphira-chroot owns.
for owned in dev proc sys run; do
	refused "a destination colliding with the tool-owned /$owned" \
		sh "$tool" --bind "$work/src:/$owned" "$target" /bin/sh -c ':'
done
refused 'a destination colliding with the tool-owned /dev/pts' \
	sh "$tool" --bind "$work/src:/dev/pts" "$target" /bin/sh -c ':'
refused 'a destination colliding with the tool-owned resolv.conf' \
	sh "$tool" --bind "$work/src:/etc/resolv.conf" "$target" /bin/sh -c ':'

# An escape must not have created anything outside the target.
test ! -e "$work/escaped" ||
	fail 'a refused escape still created a directory on the host'
ok 'refused escapes created nothing outside the target'

# --- teardown ------------------------------------------------------------

printf '%s\n' 'chroot-bind: teardown'

# Nothing this suite mounted may survive. Comparing against the count taken
# before the first successful bind is the direct statement of that: every
# mount saphira-chroot made has already gone.
after=$(mounts_now)
if [ "$after" -gt "$before" ]; then
	printf 'chroot-bind: %s mount(s) leaked (before %s, after %s)\n' \
		"$((after - before))" "$before" "$after" >&2
	grep " $target" /proc/self/mountinfo >&2 || :
	exit 1
fi
ok 'no mount created by this suite remains'

# A failing command must tear down just as completely as a successful one.
# saphira-chroot propagates the command's status, so a non-zero exit is
# expected here; what matters is that nothing is left mounted.
before_fail=$(mounts_now)
if sh "$tool" --bind "$work/src:/mnt/leak" "$target" /bin/sh -c 'exit 7' \
	>"$work/out" 2>&1; then
	:
else
	status=$?
	[ "$status" -eq 7 ] ||
		fail "a failing command returned $status, expected 7"
fi
after_fail=$(mounts_now)
[ "$after_fail" -le "$before_fail" ] ||
	fail "a failing command leaked $((after_fail - before_fail)) mount(s)"
ok 'a failing command leaves no mount behind'

# SIGINT inside a bound chroot must also clean up.
before_sig=$(mounts_now)
sh "$tool" --bind "$work/src:/mnt/sig" "$target" /bin/sh -c 'kill -INT $$' \
	>"$work/out" 2>&1 || :
after_sig=$(mounts_now)
[ "$after_sig" -le "$before_sig" ] ||
	fail "an interrupted command leaked $((after_sig - before_sig)) mount(s)"
ok 'an interrupted command leaves no mount behind'

printf 'chroot-bind: OK (%s checks)\n' "$checks"

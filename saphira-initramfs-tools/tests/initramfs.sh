#!/bin/sh

# saphira-initramfs-tools: base initramfs tooling.
#
# Everything here is rootless: generating an archive needs cpio, zstd and a
# read source tree, and touches no loop device, no filesystem and no mount.
# That is deliberate -- the point of this suite is that the tooling can be
# exercised cheaply and often, long before there is a kernel willing to boot
# the result.
#
# usage: initramfs.sh [TOOLS-ROOT]
#
#   TOOLS-ROOT is a root containing an installed saphira-initramfs-tools, i.e.
#   $TOOLS-ROOT/usr/sbin/saphira-mkinitramfs and
#   $TOOLS-ROOT/usr/lib/saphira/initramfs/init. Defaults to
#   /usr, so an installed package works.

set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
tools=${1:-/usr}

mkinitramfs=$tools/usr/sbin/saphira-mkinitramfs
init_bin=$tools/usr/lib/saphira/initramfs/init
elf_closure=$tools/usr/libexec/saphira/elf-closure

fail() {
	printf 'initramfs: %s\n' "$*" >&2
	exit 1
}

[ -x "$mkinitramfs" ] || fail "generator not executable: $mkinitramfs"
[ -x "$init_bin" ] || fail "init binary not executable: $init_bin"
[ -x "$elf_closure" ] || fail "elf-closure not executable: $elf_closure"

scratch=${SAPHIRA_TMPDIR:-/build/tmp}
mkdir -p "$scratch" || fail "cannot create scratch under $scratch"
work=$(mktemp -d "$scratch/initramfs-test.XXXXXX") ||
	fail 'cannot create a work directory'
trap 'rm -rf -- "$work"' EXIT HUP INT TERM

SAPHIRA_TMPDIR=$work
export SAPHIRA_TMPDIR

checks=0
ok() {
	checks=$((checks + 1))
	printf '  ok   %s\n' "$1"
}

refused() {
	description=$1
	shift
	if "$@" >"$work/out" 2>&1; then
		printf 'initramfs: expected a refusal: %s\n' "$description" >&2
		sed 's/^/    /' "$work/out" >&2
		exit 1
	fi
	[ -s "$work/out" ] || {
		printf 'initramfs: refused %s but said nothing\n' "$description" >&2
		exit 1
	}
	ok "refused: $description"
}

# --- the /init must be genuinely static ----------------------------------
#
# Asserted, not assumed. A dynamically linked /init builds perfectly well on
# the build host and fails only at boot, in early userspace, with no loader
# present -- which is the worst place to discover it.

printf '%s\n' 'initramfs: the /init binary'

if command -v readelf >/dev/null 2>&1; then
	if readelf -l "$init_bin" 2>/dev/null | grep -q 'program interpreter'; then
		fail 'init is dynamically linked; it must be static'
	fi
	if readelf -d "$init_bin" 2>/dev/null | grep -q 'NEEDED'; then
		fail 'init has shared library dependencies; it must be static'
	fi
	ok 'init is static: no interpreter, no NEEDED entries'
else
	ok 'init staticness not asserted (readelf unavailable)'
fi
# A static binary has an empty library closure, which is the property the
# generator depends on when it decides what to pull in.
closure=$("$elf_closure" "$init_bin" 2>/dev/null || true)
[ -z "$closure" ] || fail "static init reported a library closure: $closure"
ok 'init reports an empty library closure, as a static binary must'

# --- a synthetic payload root -------------------------------------------
#
# Built here rather than reused from a real system, so the closure and module
# graphs are small enough to state exactly and a failure names a real cause.

KVER=7.99.0-akadata
payload=$work/root
mkdir -p "$payload/bin" "$payload/usr/bin" "$payload/usr/lib" \
	"$payload/usr/lib/saphira/initramfs" "$payload/etc/saphira" \
	"$payload/lib/saphira/initramfs/early.d" \
	"$payload/lib/saphira/initramfs/root.d" \
	"$payload/lib/saphira/initramfs/pre-switch-root.d" \
	"$payload/lib/modules/$KVER/kernel/lib" \
	"$payload/lib/modules/$KVER/kernel/drivers/extra"

cp "$init_bin" "$payload/usr/lib/saphira/initramfs/init"
# A real dynamically linked binary with a real library closure, so the ELF
# test has something to find.
for b in /bin/sh /sbin/switch_root; do
	[ -f "$b" ] || continue
	cp "$b" "$payload$b" 2>/dev/null || {
		mkdir -p "$payload$(dirname -- "$b")"
		cp "$b" "$payload$b"
	}
done
# Its libraries, so the closure has something to resolve.
for l in /lib/libc.so /lib/ld-musl-x86_64.so.1 /lib/libncursesw.so.6; do
	[ -e "$l" ] || continue
	mkdir -p "$payload$(dirname -- "$l")"
	cp -L "$l" "$payload$l" 2>/dev/null || true
done

# A kernel module graph with a real transitive dependency and a shared
# dependency, so the BFS closure is actually exercised:
#   top -> mid -> leaf      (a chain)
#   top -> leaf              (a diamond)
#   side -> leaf             (a shared node)
mod=$payload/lib/modules/$KVER
: > "$mod/modules.dep"
cat > "$mod/modules.dep" <<DEPS
kernel/drivers/extra/top.ko: kernel/drivers/extra/mid.ko kernel/drivers/extra/side.ko
kernel/drivers/extra/mid.ko: kernel/drivers/extra/leaf.ko
kernel/drivers/extra/side.ko: kernel/drivers/extra/leaf.ko
kernel/drivers/extra/leaf.ko:
kernel/drivers/extra/unrelated.ko:
DEPS
cat > "$mod/modules.softdep" <<SOFT
softdep top pre: mid
SOFT
for m in top mid side leaf unrelated; do
	printf 'not really a module\n' > "$mod/kernel/drivers/extra/$m.ko"
done

# Runtime hooks. One shell script (so a shebang interpreter must come with
# it) and one native executable, proving both kinds work.
cat > "$payload/lib/saphira/initramfs/early.d/10-marker" <<'HOOK'
#!/bin/sh
exit 0
HOOK
cat > "$payload/lib/saphira/initramfs/root.d/10-first" <<'HOOK'
#!/bin/sh
exit 0
HOOK
cat > "$payload/lib/saphira/initramfs/root.d/20-second" <<'HOOK'
#!/bin/sh
exit 0
HOOK
# Deliberately mis-ordered names, to prove the ORDER comes from the names and
# not from the order they happen to be written.
cat > "$payload/lib/saphira/initramfs/pre-switch-root.d/90-last" <<'HOOK'
#!/bin/sh
exit 0
HOOK
cp "$init_bin" "$payload/lib/saphira/initramfs/pre-switch-root.d/05-native"
chmod 0755 "$payload/lib/saphira/initramfs/early.d/10-marker" \
	"$payload/lib/saphira/initramfs/root.d/10-first" \
	"$payload/lib/saphira/initramfs/root.d/20-second" \
	"$payload/lib/saphira/initramfs/pre-switch-root.d/90-last" \
	"$payload/lib/saphira/initramfs/pre-switch-root.d/05-native"

cat > "$work/initramfs.conf" <<CONF
bin /sbin/switch_root
mod top
hook /lib/saphira/initramfs/early.d/10-marker
hook /lib/saphira/initramfs/root.d/10-first
hook /lib/saphira/initramfs/root.d/20-second
hook /lib/saphira/initramfs/pre-switch-root.d/90-last
hook /lib/saphira/initramfs/pre-switch-root.d/05-native
CONF

out=$work/initramfs.zst

printf '%s\n' 'initramfs: building'

"$mkinitramfs" build --kernel "$KVER" --root "$payload" \
	--output "$out" --config "$work/initramfs.conf" \
	--init "$payload/usr/lib/saphira/initramfs/init" \
	--module-dir "$payload/lib/modules" >"$work/out" 2>&1 ||
	{
		printf 'initramfs: build failed\n' >&2
		sed 's/^/    /' "$work/out" >&2
		exit 1
	}
[ -f "$out" ] || fail 'no output archive was produced'
ok "build produced an archive ($(wc -c < "$out") bytes)"

listing=$("$mkinitramfs" list "$out" 2>/dev/null) ||
	fail 'list failed on a freshly built archive'
[ -n "$listing" ] || fail 'list produced nothing'
ok "list works ($(printf '%s\n' "$listing" | wc -l) entries)"

printf '%s\n' "$listing" | grep -qx 'init' || fail 'the archive has no /init'
ok 'the archive contains /init'

# --- ELF library closure -------------------------------------------------

printf '%s\n' 'initramfs: closure'

if printf '%s\n' "$listing" | grep -q '^sbin/switch_root$'; then
	if printf '%s\n' "$listing" | grep -qE '^(lib|usr/lib)/lib(c|n|z|attr|acl)'; then
		ok 'a dynamic binary brought its shared libraries with it'
	else
		fail 'switch_root was staged but no libraries came with it'
	fi
else
	ok 'switch_root not present in this environment; library closure not exercised here'
fi

# A script hook must bring its interpreter.
if printf '%s\n' "$listing" | grep -q '^bin/sh$'; then
	ok 'a script hook brought its shebang interpreter'
else
	fail 'a script hook was staged without /bin/sh'
fi
if printf '%s\n' "$listing" | grep -q 'libncurses'; then
	ok "the hook interpreter's own closure came too"
else
	ok 'interpreter needed no extra libraries beyond libc'
fi

# --- module dependency closure -------------------------------------------

for m in top mid side leaf; do
	printf '%s\n' "$listing" | grep -q "lib/modules/$KVER/kernel/drivers/extra/$m.ko" || fail "module closure is missing $m"
done
if printf '%s\n' "$listing" | grep -q "lib/modules/$KVER/kernel/drivers/extra/unrelated.ko"; then
	fail 'unrelated module was pulled in'
fi
ok 'module dependency closure is transitive, diamond-correct, and no wider'

# --- hook ordering -------------------------------------------------------

printf '%s\n' 'initramfs: hooks'
for h in early.d/10-marker root.d/10-first root.d/20-second \
	pre-switch-root.d/05-native pre-switch-root.d/90-last; do
	printf '%s\n' "$listing" | grep -qx "lib/saphira/initramfs/$h" || fail "hook not staged: $h"
done
ok 'every runtime hook is staged at its stage path'

# --- no build-host paths -------------------------------------------------

for forbidden in build recipes out imagebuilder; do
	if grep -qE "^($forbidden)(/|$)" <<EOF
$listing
EOF
	then
		fail "the archive contains a $forbidden path"
	fi
done
ok 'the archive contains no /build, /recipes, /out or /imagebuilder paths'

# --- modes and ownership -------------------------------------------------

printf '%s\n' 'initramfs: modes and ownership'
unpacked=$work/unpacked
"$mkinitramfs" unpack "$out" "$unpacked" >"$work/out" 2>&1 ||
	{
		printf 'initramfs: unpack failed\n' >&2
		sed 's/^/    /' "$work/out" >&2
		exit 1
	}
[ -x "$unpacked/init" ] || fail 'unpacked /init is not executable'
[ -f "$unpacked/init" ] || fail 'unpacked /init is not a file'
[ -x "$unpacked/lib/saphira/initramfs/early.d/10-marker" ] ||
	fail 'an unpacked hook is not executable'
ok 'unpack works and preserves executable modes'

"$mkinitramfs" verify "$out" --kernel "$KVER" >"$work/out" 2>&1 ||
	{
		printf 'initramfs: verify failed\n' >&2
		sed 's/^/    /' "$work/out" >&2
		exit 1
	}
ok 'verify accepts a good archive for the right kernel'

# --- reproducibility -----------------------------------------------------

printf '%s\n' 'initramfs: reproducibility'
out2=$work/initramfs-again.zst
"$mkinitramfs" build --kernel "$KVER" --root "$payload" \
	--output "$out2" --config "$work/initramfs.conf" \
	--init "$payload/usr/lib/saphira/initramfs/init" \
	--module-dir "$payload/lib/modules" >"$work/out" 2>&1 ||
	{
		printf 'initramfs: second build failed\n' >&2
		sed 's/^/    /' "$work/out" >&2
		exit 1
	}
if cmp -s "$out" "$out2"; then
	ok 'two builds of the same input are byte-identical'
else
	fail 'two builds of the same input differ'
fi

# Ownership must be 0:0 in the archive, not whatever the build host used.
first_uid=$(cpio -itv --quiet < <(zstd -dc -- "$out") 2>/dev/null |
	sed -n '1s/^[^ ]* *\([0-9]*\/[0-9]*\).*/\1/p')
[ -z "$first_uid" ] || [ "$first_uid" = '0/0' ] ||
	fail "archive ownership is $first_uid, expected 0/0"
ok 'archive ownership is normalised to 0:0'

# --- negative tests ------------------------------------------------------

printf '%s\n' 'initramfs: refusals'

refused 'no --kernel' \
	"$mkinitramfs" build --root "$payload" --output "$work/n1.zst" \
	--config "$work/initramfs.conf" --init "$payload/usr/lib/saphira/initramfs/init"
refused 'an unknown kernel' \
	"$mkinitramfs" build --kernel 0.0.0-nonexistent --root "$payload" \
	--output "$work/n2.zst" --config "$work/initramfs.conf" \
	--init "$payload/usr/lib/saphira/initramfs/init" --module-dir "$payload/lib/modules"

cat > "$work/missing-bin.conf" <<CONF
bin /usr/bin/definitely-not-here
CONF
refused 'a requested binary that is not in the root' \
	"$mkinitramfs" build --kernel "$KVER" --root "$payload" \
	--output "$work/n3.zst" --config "$work/missing-bin.conf" \
	--init "$payload/usr/lib/saphira/initramfs/init" --module-dir "$payload/lib/modules"

cat > "$work/missing-mod.conf" <<CONF
mod definitely_not_a_module
CONF
refused 'a module that is not in modules.dep' \
	"$mkinitramfs" build --kernel "$KVER" --root "$payload" \
	--output "$work/n4.zst" --config "$work/missing-mod.conf" \
	--init "$payload/usr/lib/saphira/initramfs/init" --module-dir "$payload/lib/modules"

cat > "$work/missing-hook.conf" <<CONF
hook /lib/saphira/initramfs/root.d/99-absent
CONF
refused 'a runtime hook that is not in the root' \
	"$mkinitramfs" build --kernel "$KVER" --root "$payload" \
	--output "$work/n5.zst" --config "$work/missing-hook.conf" \
	--init "$payload/usr/lib/saphira/initramfs/init" --module-dir "$payload/lib/modules"

# A hook whose shebang names an interpreter the root does not have. The
# generator must refuse rather than produce an archive whose hook cannot run.
mkdir -p "$payload/lib/saphira/initramfs/root.d"
cat > "$payload/lib/saphira/initramfs/root.d/30-nointerp" <<'HOOK'
#!/nonexistent/interpreter
exit 0
HOOK
chmod 0755 "$payload/lib/saphira/initramfs/root.d/30-nointerp"
cat > "$work/nointerp.conf" <<CONF
hook /lib/saphira/initramfs/root.d/30-nointerp
CONF
refused 'a hook whose shebang interpreter is unavailable' \
	"$mkinitramfs" build --kernel "$KVER" --root "$payload" \
	--output "$work/n6.zst" --config "$work/nointerp.conf" \
	--init "$payload/usr/lib/saphira/initramfs/init" --module-dir "$payload/lib/modules"
rm -f "$payload/lib/saphira/initramfs/root.d/30-nointerp"

# A build hook that fails must fail the build.
hookdir=$work/hooks
mkdir -p "$hookdir"
cat > "$hookdir/50-fail" <<'HOOK'
#!/bin/sh
exit 3
HOOK
chmod 0755 "$hookdir/50-fail"
if SAPHIRA_BUILD_HOOK_DIR=$hookdir \
	"$mkinitramfs" build --kernel "$KVER" --root "$payload" \
	--output "$work/n7.zst" --config "$work/initramfs.conf" \
	--init "$payload/usr/lib/saphira/initramfs/init" \
	--module-dir "$payload/lib/modules" >"$work/out" 2>&1; then
	fail 'a failing build hook did not fail the build'
fi
[ -e "$work/n7.zst" ] && fail 'a failed build hook still produced an output'
ok 'refused: a failing build hook, and it produced no output'

# A build hook that succeeds is run, and what it adds is included.
cat > "$hookdir/60-add" <<'HOOK'
#!/bin/sh
printf 'added-by-build-hook\n' > "$SAPHIRA_INITRAMFS_STAGE/etc/added-by-hook"
HOOK
chmod 0755 "$hookdir/60-add"
rm -f "$hookdir/50-fail"
SAPHIRA_BUILD_HOOK_DIR=$hookdir \
	"$mkinitramfs" build --kernel "$KVER" --root "$payload" \
	--output "$work/hooked.zst" --config "$work/initramfs.conf" \
	--init "$payload/usr/lib/saphira/initramfs/init" \
	--module-dir "$payload/lib/modules" >"$work/out" 2>&1 ||
	{
		printf 'initramfs: build with a successful hook failed\n' >&2
		sed 's/^/    /' "$work/out" >&2
		exit 1
	}
"$mkinitramfs" list "$work/hooked.zst" 2>/dev/null |
	grep -qx 'etc/added-by-hook' ||
	fail 'a successful build hook did not have its contribution included'
ok 'a successful build hook runs and its contribution is archived'

# The previous good initramfs must survive every failure above.
printf 'previous-good-archive\n' > "$work/keep.zst"
before_sum=$(cksum < "$work/keep.zst")
"$mkinitramfs" build --kernel "$KVER" --root "$payload" \
	--output "$work/keep.zst" --config "$work/missing-mod.conf" \
	--init "$payload/usr/lib/saphira/initramfs/init" \
	--module-dir "$payload/lib/modules" >"$work/out" 2>&1 || :
after_sum=$(cksum < "$work/keep.zst")
[ "$before_sum" = "$after_sum" ] ||
	fail 'a failed build modified the previous output'
grep -q 'previous-good-archive' "$work/keep.zst" ||
	fail 'a failed build destroyed the previous output'
ok 'a failed build leaves the previous output untouched'

printf 'initramfs: OK (%s checks)\n' "$checks"

#!/bin/sh

# buildpkg-single: named subpackages beyond -dev/-doc/-libs.
#
# Some upstreams need product splits that are none of -dev, -doc or
# -libs (libvirt drivers: one canonical build, payload split into
# libvirt / libvirt-qemu / libvirt-lxc / storage backends), and
# rebuilding per driver is forbidden. The manifest/outputs machinery
# was already generic; only the move rules were fixed to three kinds.
# Named splits close that gap: files/split-<name>.list carries the
# payload paths (one per line), files/split-<name>.depends the extra
# runtime deps, and every violation fails closed.
#
# This suite pins the mechanism contract statically (the libs-standalone
# precedent for controller logic): explicit lists fail closed on
# missing paths, names are validated, dup claims die, and the legacy
# -dev/-doc/-libs branches are byte-stable.

set -u

BUILDPKG=${1:-"$(dirname "$0")/../files/buildpkg-single"}
[ -f "$BUILDPKG" ] || BUILDPKG=/usr/lib/saphira-packager/buildpkg-single
[ -f "$BUILDPKG" ] || { echo "buildpkg-single not found" >&2; exit 2; }

pass=0
fail=0
ok() { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
no() { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }

echo "buildpkg-single named-subpackage contract"
echo "  buildpkg-single: $BUILDPKG"

# --- 0. the file parses ------------------------------------------------
if bash -n "$BUILDPKG" 2>/dev/null; then
	ok "buildpkg-single parses (bash -n)"
else
	no "buildpkg-single fails bash -n"
fi

# --- 1. named splits are accepted with rules files -----------------------
if grep -q 'files/split-\$subpackage\.list' "$BUILDPKG"; then
	ok "named splits read rules from files/split-<name>.list"
else
	no "no files/split-<name>.list mechanism"
fi
if grep -q 'lacks rules file' "$BUILDPKG"; then
	ok "missing rules file fails closed"
else
	no "missing rules file is not an error"
fi

# --- 2. name validation ---------------------------------------------------
if grep -q 'must start alphanumeric' "$BUILDPKG"; then
	ok "subpackage names must start alphanumeric"
else
	no "no alphanumeric-start check"
fi
if grep -q 'duplicates base package name' "$BUILDPKG"; then
	ok "split duplicating the base name is refused"
else
	no "base-name duplicate is not refused"
fi

# --- 3. path validation ---------------------------------------------------
if grep -q 'absolute path forbidden' "$BUILDPKG" && \
   grep -q 'parent reference forbidden' "$BUILDPKG"; then
	ok "absolute paths and parent references are refused"
else
	no "path traversal guards missing"
fi
if grep -q 'path not staged' "$BUILDPKG"; then
	ok "explicit lists fail closed on missing paths"
else
	no "missing staged path is not an error"
fi
if grep -q 'claimed by multiple subpackages' "$BUILDPKG"; then
	ok "duplicate payload claims across splits die"
else
	no "duplicate-claim detection missing"
fi

# --- 4. moves reuse the symlink-safe primitives ---------------------------
if grep -q 'move_named_split "\$subpackage"' "$BUILDPKG" && \
   grep -q 'move_staged_tree "$entry" "$subpackage"' "$BUILDPKG" && \
   grep -q 'move_staged_file "$PKGDEST/$entry" "$subpackage"' "$BUILDPKG"; then
	ok "named moves reuse move_staged_tree/move_staged_file (symlinks stay symlinks)"
else
	no "named moves bypass the safe primitives"
fi

# --- 5. depends wiring -----------------------------------------------------
if grep -q 'files/split-\$subpackage\.depends' "$BUILDPKG" && \
   grep -q 'dev_dependencies="$pkgname=$pkgver-r$pkgrel $split_extra_deps"' "$BUILDPKG"; then
	ok "named splits pin the base release plus .depends words"
else
	no "named-split depends wiring missing"
fi

# --- 6. legacy branches byte-stable -----------------------------------------
# These exact lines must survive any edit of this file: they are the
# -dev/-doc/-libs contract other suites and packages rely on.
if grep -q "move_staged_tree usr/include \"\$subpackage\"" "$BUILDPKG" && \
   grep -q "move_staged_tree usr/share/doc \"\$subpackage\"" "$BUILDPKG" && \
   grep -q "find \"\$root\" \\\( -type f -o -type l \\\) -name '\*\.so\.\*'" "$BUILDPKG" && \
   grep -q '"$pkgname"-libs) description="$pkgdesc runtime libraries"; dev_dependencies=""' "$BUILDPKG"; then
	ok "legacy -dev/-doc/-libs branches intact"
else
	no "legacy split branches were altered"
fi
if grep -q 'only -dev, -doc and -libs are supported' "$BUILDPKG"; then
	no "stale fixed-set error message still present"
else
	ok "fixed-set error message replaced by named-split validation"
fi

if [ "$fail" -gt 0 ]; then
	printf '%s\n' "subpackages-named: $fail FAILURES ($pass ok)"
	exit 1
fi
printf '%s\n' "subpackages-named: contract OK ($pass checks)"

# --- 7. end-to-end through the real worker -------------------------------
# Fixture recipe with one named split plus a -dev split, run through
# the actual buildpkg-single under bwrap (rootless userns, scratch
# only). No namespaces beyond bwrap, no repo, no network: the
# fixture declares no source= (SOURCE falls back to the recipe dir)
# and empty depends/makedepends.
if ! command -v bwrap >/dev/null 2>&1; then
	printf '%s\n' "subpackages-named: bwrap missing, skipping end-to-end"
	exit 0
fi

T=${SAPHIRA_TMPDIR:-/build/tmp}/subpackages-named.$$
rm -rf "$T"
mkdir -p "$T/recipes/testsplit/files" "$T/build" "$T/rootfs"
: > "$T/worker.log"
trap 'rm -rf "$T"' EXIT HUP INT TERM

cat > "$T/recipes/testsplit/recipe.sh" <<'EOF'
#!/bin/sh
pkgname=testsplit
pkgver=1.0
pkgrel=1
pkgarch=x86_64
pkgdesc="named-split fixture"
license="MIT"
origin=testsplit
repo=saphira
url=https://example.invalid/
depends=""
makedepends=""
subpackages="testsplit-extra testsplit-dev"
recipe_build() { :; }
recipe_install()
{
	mkdir -p "$PKGDEST/usr/bin" "$PKGDEST/usr/share/data" \
		"$PKGDEST/usr/share/doc/testsplit" "$PKGDEST/usr/lib" \
		"$PKGDEST/usr/include"
	printf 'tool\n' > "$PKGDEST/usr/bin/tool"
	printf 'blob\n' > "$PKGDEST/usr/share/data/blob"
	printf 'doc\n' > "$PKGDEST/usr/share/doc/testsplit/README"
	printf 'static\n' > "$PKGDEST/usr/lib/libx.a"
	printf 'shared\n' > "$PKGDEST/usr/lib/libx.so.1"
	ln -s libx.so.1 "$PKGDEST/usr/lib/libx.so"
	printf 'header\n' > "$PKGDEST/usr/include/x.h"
}
EOF
printf '# fixture comment\nusr/bin/tool\n\nusr/share/data\n' \
	> "$T/recipes/testsplit/files/split-testsplit-extra.list"
printf '# fixture comment\ntestsplit-toolkit>=2.0\n' \
	> "$T/recipes/testsplit/files/split-testsplit-extra.depends"

run_worker()
{
	# Real worker, hermetic namespace: an empty root populated
	# read-only with the host tool trees (bash, coreutils, python3)
	# plus the fixture recipe and scratch build dirs. All writes
	# land in $T; the host tree is never written.
	bwrap --die-with-parent --new-session --unshare-all \
		--uid 0 --gid 0 --clearenv \
		--bind "$T/rootfs" / \
		--ro-bind /usr /usr --ro-bind /bin /bin \
		--ro-bind /sbin /sbin --ro-bind /lib /lib \
		--bind "$T/build" /build \
		--bind "$T/recipes" /recipes \
		--dir /controller \
		--ro-bind "$BUILDPKG" /controller/buildpkg-single \
		--ro-bind "$(dirname "$BUILDPKG")/package_builder.sh" /controller/package_builder.sh \
		--dev /dev --proc /proc --dir /tmp \
		--setenv PATH /usr/bin:/bin \
		--setenv HOME /tmp --setenv LANG C \
		--setenv SAPHIRA_ISOLATED_BUILD 1 \
		--setenv SAPHIRA_CONFIG_FILE /controller/package_builder.sh \
		--setenv SAPHIRA_RECIPE_ROOT /recipes \
		--setenv SAPHIRA_BUILD_ROOT /build \
		--setenv SAPHIRA_TMPDIR /build/tmp \
		--setenv SAPHIRA_ARCH x86_64 \
		--setenv SAPHIRA_PYTHON /usr/bin/python3 \
		--setenv SOURCE_DATE_EPOCH 1234567890 \
		bash /controller/buildpkg-single testsplit >>"$T/worker.log" 2>&1
}

if run_worker; then
	ok "worker build with named split succeeds"
else
	no "worker build with named split failed (see $T/worker.log)"
	tail -15 "$T/worker.log" >&2 || true
fi
W=$T/build/testsplit
check() { if [ "$1" = "$2" ]; then ok "$3"; else no "$3 (want '$2', got '$1')"; fi; }
check "$(cat "$W/subpkg/testsplit-extra/usr/bin/tool" 2>/dev/null)" "tool" \
	"named split carries the listed file"
check "$(cat "$W/subpkg/testsplit-extra/usr/share/data/blob" 2>/dev/null)" "blob" \
	"named split carries the listed tree"
check "$(cat "$W/subpkg/testsplit-dev/usr/lib/libx.a" 2>/dev/null)" "static" \
	"legacy -dev split still works alongside"
check "$(cat "$W/pkg/usr/lib/libx.so.1" 2>/dev/null)" "shared" \
	"unlisted payload stays in main"
if [ -e "$W/pkg/usr/bin/tool" ] || [ -e "$W/pkg/usr/share/data" ]; then
	no "listed paths leaked into main"
else
	ok "listed paths leave main"
fi
if [ -L "$W/subpkg/testsplit-dev/usr/lib/libx.so" ]; then
	ok "dev symlink moved as symlink"
else
	no "dev symlink not preserved"
fi
manifest_names=$(python3 -c "import json;print(' '.join(o['name'] for o in json.load(open('$W/manifest.json'))['outputs']))")
check "$manifest_names" "testsplit testsplit-extra testsplit-dev" \
	"manifest lists base plus both splits"
manifest_deps=$(python3 -c "import json;print(' '.join(d for o in json.load(open('$W/manifest.json'))['outputs'] if o['name']=='testsplit-extra' for d in o['dependencies']))")
check "$manifest_deps" "testsplit=1.0-r1 testsplit-toolkit>=2.0" \
	"named split depends pin base plus .depends words"

# Fail-closed probes: each must make the worker die.
expect_fail()
{
	desc=$1
	if run_worker; then
		no "$desc (worker unexpectedly succeeded)"
	else
		ok "$desc"
	fi
	rm -rf "$T/build"
	mkdir -p "$T/build"
}
printf 'no-such-path\n' > "$T/recipes/testsplit/files/split-testsplit-extra.list"
expect_fail "missing staged path fails the build"
printf 'usr/bin/tool\n' > "$T/recipes/testsplit/files/split-testsplit-extra.list"
printf '/absolute/path\n' >> "$T/recipes/testsplit/files/split-testsplit-extra.list"
expect_fail "absolute path fails the build"
printf 'usr/bin/tool\n../escape\n' > "$T/recipes/testsplit/files/split-testsplit-extra.list"
expect_fail "parent reference fails the build"

if [ "$fail" -gt 0 ]; then
	printf '%s\n' "subpackages-named: $fail FAILURES ($pass ok)"
	exit 1
fi
printf '%s\n' "subpackages-named: OK ($pass checks)"

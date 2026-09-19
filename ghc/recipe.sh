#!/bin/sh

# The Glasgow Haskell Compiler 9.14.1 (LTS line).
#
# ghci, runghc, ghc-pkg and haddock are NOT separate recipes: upstream
# ships them all from this single source distribution (release notes
# "Included libraries" table: ghci 9.14.1, haddock-api 2.33.0, plus
# the ghc/runghc/ghc-pkg executables). One upstream tarball means one
# recipe; the executables all land in the main package, haddock HTML
# and manuals split to ghc-doc.
#
# There is deliberately no ghc-dev split: a compiler is self-contained
# (toolchain rule, gcc precedent). The .hi/.a interface libraries under
# /usr/lib/ghc-9.14.1 are required to compile anything, so they stay in
# main; only documentation splits out.
#
# Nothing moves to /lib (runtime-placement rule): no /bin|/sbin binary
# links the Haskell toolchain, so the whole payload stays under /usr.
#
# Build flow (upstream packager path, hadrian/bootstrap/README.md):
#   1. pinned bootstrap GHC bindist (build tool only, never shipped);
#   2. hadrian/bootstrap/bootstrap.py builds Hadrian WITHOUT cabal
#      ("for packagers"), downloading its pinned dep plan;
#   3. ./configure --prefix + hadrian build + binary-dist;
#   4. the produced bindist installs with DESTDIR into PKGDEST.
# The in-tree bootstrap plans stop at 9_12_2, so the bootstrap compiler
# is 9.12.4 (prior major, standard N-2 practice) with the newest 9.12
# plan. If the plan rejects the newer point release, the failure is
# loud (bootstrap.py asserts versions) and the recipe pins 9.12.2.

pkgname=ghc
pkgver=9.14.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="The Glasgow Haskell Compiler 9.14.1 with ghci, runghc and haddock"
license=BSD-3-Clause
origin=ghc
repo=saphira
url=https://www.haskell.org/ghc/
source=https://downloads.haskell.org/ghc/9.14.1/ghc-9.14.1-src.tar.xz
sha256=2a83779c9af86554a3289f2787a38d6aa83d00d136aa9f920361dd693c101e77

depends="
    gmp
    libffi
    musl
    ncurses
    zlib
"
makedepends="
    alex
    bash
    binutils
    curl
    gcc
    gmp-dev
    happy
    libffi-dev
    make
    ncurses-dev
    perl
    pkgconf
    python3
    zlib-dev
"
# Only -doc splits (haddock HTML, users guide, man pages). If the
# default Hadrian flavour ever stops emitting them, the file gate
# skips the stale claims (rustc precedent) instead of failing.
subpackages="$pkgname-doc"

fatal()
{
	printf 'ghc: %s\n' "$1" >&2
	exit 1
}

install_bootstrap_ghc()
{
	expected=$(awk -F'|' '$5 == "ghc-9.12.4-x86_64-alpine3_20-linux.tar.xz" { print $4; exit }' \
		"$RECIPE_DIR/bootstrap.lock")
	test -n "$expected" || fatal "bootstrap GHC is not locked"
	curl -fsSL --retry 3 --output "$BUILDDIR/bootstrap-ghc.tar.xz" \
		"https://downloads.haskell.org/ghc/9.12.4/ghc-9.12.4-x86_64-alpine3_20-linux.tar.xz" ||
		fatal "failed to download bootstrap GHC"
	printf '%s  %s\n' "$expected" "$BUILDDIR/bootstrap-ghc.tar.xz" | sha256sum -c - ||
		fatal "bootstrap GHC checksum mismatch"
	mkdir -p "$BUILDDIR/boot-src"
	tar -xf "$BUILDDIR/bootstrap-ghc.tar.xz" -C "$BUILDDIR/boot-src"
	boot_top=$(tar -tf "$BUILDDIR/bootstrap-ghc.tar.xz" |
		awk -F/ 'NF { print $1; exit }')
	test -n "$boot_top" || fatal "bootstrap archive has no top-level directory"
	cd "$BUILDDIR/boot-src/$boot_top"
	# layout-exception (bootstrap only): scratch prefix, never
	# installed - GNU dir flags are noise here. The packaged builds
	# below carry the full explicit baseline.
	./configure --prefix="$BUILDDIR/bootstrap" >/dev/null ||
		fatal "bootstrap GHC configure failed"
	make install >/dev/null ||
		fatal "bootstrap GHC install failed"
	test -x "$BUILDDIR/bootstrap/bin/ghc" || fatal "bootstrap GHC has no ghc binary"
	"$BUILDDIR/bootstrap/bin/ghc" --version | grep -q "9.12.4" ||
		fatal "unexpected bootstrap GHC version"
}

recipe_build()
{
	install_bootstrap_ghc
	export PATH="$BUILDDIR/bootstrap/bin:$PATH"
	cd "$SRC"
	# Flag confidence: --prefix is certain (bindist install flow);
	# bootstrap.py -w/-d and `binary-dist` are upstream-documented
	# (hadrian/bootstrap/README.md, GHC building guide) and fail
	# visibly on misuse. The 9_12_2 plan against a 9.12.4 compiler
	# is the one deliberate stretch, asserted by bootstrap.py itself.
	python3 hadrian/bootstrap/bootstrap.py \
		-w "$BUILDDIR/bootstrap/bin/ghc" \
		-d hadrian/bootstrap/plan-bootstrap-9_12_2.json ||
		fatal "hadrian bootstrap failed"
	test -x _build/bin/hadrian || fatal "no hadrian binary produced"
	./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var || fatal "configure failed"
	./hadrian/build -j"${JOBS:-$(nproc)}" || fatal "hadrian build failed"
	./hadrian/build binary-dist -j"${JOBS:-$(nproc)}" || fatal "binary-dist failed"
	bindist=$(echo _build/bindist/ghc-9.14.1-*.tar.xz)
	test -f "$bindist" || fatal "no bindist produced"
	printf '%s\n' "$bindist" > "$BUILDDIR/bindist-path"
}

recipe_install()
{
	bindist=$(cat "$BUILDDIR/bindist-path")
	mkdir -p "$BUILDDIR/bindist"
	tar -xf "$SRC/$bindist" -C "$BUILDDIR/bindist"
	inst_top=$(tar -tf "$SRC/$bindist" | awk -F/ 'NF { print $1; exit }')
	cd "$BUILDDIR/bindist/$inst_top"
	./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var || fatal "bindist configure failed"
	make install DESTDIR="$PKGDEST" || fatal "bindist install failed"
	# Skew checks: the staged toolchain must identify as this exact
	# release and compile against the actual Saphira musl.
	"$PKGDEST/usr/bin/ghc" --version | grep -q "9.14.1" ||
		fatal "staged ghc is not 9.14.1"
	"$PKGDEST/usr/bin/ghc-pkg" --version | grep -q "9.14.1" ||
		fatal "staged ghc-pkg is not 9.14.1"
	"$PKGDEST/usr/bin/ghc-pkg" list | grep -q "base-4.22" ||
		fatal "staged global db has no base-4.22"
	printf 'main = putStrLn "hatchling"\n' > "$BUILDDIR/hello.hs"
	"$PKGDEST/usr/bin/ghc" -o "$BUILDDIR/hello" "$BUILDDIR/hello.hs" ||
		fatal "staged ghc cannot compile"
	"$BUILDDIR/hello" | grep -q hatchling || fatal "staged ghc produced a broken binary"
	printf 'putStrLn "runghc-ok"\n' > "$BUILDDIR/runghc.hs"
	"$PKGDEST/usr/bin/runghc" "$BUILDDIR/runghc.hs" | grep -q runghc-ok ||
		fatal "staged runghc is broken"
}

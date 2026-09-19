#!/bin/sh

# Happy parser generator for Haskell (yacc equivalent).
#
# Second link of the native Haskell closure (see alex recipe header):
#   alex, happy (bootstrap GHC) -> ghc (native) -> cabal-install -> stack, hls
#
# The happy-2.2 frontend sdist does not contain its backend: the exe
# links happy-lib ==2.2 (separate Hackage package, same upstream
# mono-repo). happy-lib is therefore pinned in bootstrap.lock
# (rustc multi-component precedent) and built first into a scratch
# package db; both use the dependency-free Setup.hs flow against the
# bootstrap GHC (Cabal library ships inside the bindist).
#
# --datadir is pinned to the FINAL /usr path at configure: the
# Paths_happy_lib module baked into the binary must resolve
# HappyTemplate.hs at its installed location, not staging. The
# Haskell code links statically, so no library registration ships:
# only the binary plus data-files land in the package.

pkgname=happy
pkgver=2.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Happy parser generator for Haskell"
license=BSD-2-Clause
origin=happy
repo=saphira
url=https://www.haskell.org/happy/
source=https://hackage.haskell.org/package/happy-2.2/happy-2.2.tar.gz
sha256=2e9345c99a61bc29b5a1b9d5c1ea791cbea219499a4c01ed71f33c3af34a5eb0

depends="gmp zlib"
makedepends="
    binutils
    curl
    gcc
"

fatal()
{
	printf 'happy: %s\n' "$1" >&2
	exit 1
}

# Pinned bootstrap GHC (musl bindist, build tool only). Same window as
# alex: the sdist is tested with ghc ==9.14.1 and ==9.12.2, so 9.12.4
# applies. happy-lib ships no Setup-independent surprises either
# (build-type Simple, boot-library deps only).
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
	# layout-exception: bootstrap GHC configures into a disposable
	# scratch prefix (never installed); GNU dir flags are noise here.
	# The real build below uses cabal Setup.hs configure with Haskell
	# path flags (--datadir/--docdir), not GNU dir flags.
	./configure --prefix="$BUILDDIR/bootstrap" >/dev/null ||
		fatal "bootstrap GHC configure failed"
	make install >/dev/null ||
		fatal "bootstrap GHC install failed"
	test -x "$BUILDDIR/bootstrap/bin/ghc" || fatal "bootstrap GHC has no ghc binary"
	"$BUILDDIR/bootstrap/bin/ghc" --version | grep -q "9.12.4" ||
		fatal "unexpected bootstrap GHC version"
}

fetch_locked()
{
	name=$1
	entry=$(awk -F'|' -v name="$name" '$1 == name { print; exit }' \
		"$RECIPE_DIR/bootstrap.lock")
	test -n "$entry" || fatal "bootstrap component is not locked: $name"
	url=${entry#*|*|}; url=${url%%|*}
	sha=${entry#*|*|*|}; sha=${sha%%|*}
	base=$(basename "$url")
	curl -fsSL --retry 3 --output "$BUILDDIR/$base" "$url" ||
		fatal "failed to download bootstrap component: $name"
	printf '%s  %s\n' "$sha" "$BUILDDIR/$base" | sha256sum -c - ||
		fatal "bootstrap component checksum mismatch: $name"
	printf '%s\n' "$BUILDDIR/$base"
}

recipe_build()
{
	install_bootstrap_ghc
	export PATH="$BUILDDIR/bootstrap/bin:$PATH"
	"$BUILDDIR/bootstrap/bin/ghc-pkg" init "$BUILDDIR/pkgdb" ||
		fatal "cannot init scratch package db"
	# Backend library first, registered only in the scratch db: the
	# frontend links it statically, so no registration ships.
	libball=$(fetch_locked happy-lib-src)
	mkdir -p "$BUILDDIR/happy-lib"
	tar -xf "$libball" -C "$BUILDDIR/happy-lib" --strip-components=1
	cd "$BUILDDIR/happy-lib"
	runghc Setup.hs configure --package-db="$BUILDDIR/pkgdb" \
		--prefix=/usr --datadir=/usr/share/happy-lib-2.2 || fatal "happy-lib configure failed"
	runghc Setup.hs build || fatal "happy-lib build failed"
	# Registered inplace: the frontend links the build-tree library
	# statically, so only the binary plus data-files ship (the copy
	# of both components happens in recipe_install).
	runghc Setup.hs register --inplace || fatal "happy-lib register failed"
	# Frontend against the scratch db.
	cd "$SRC"
	runghc Setup.hs configure --package-db="$BUILDDIR/pkgdb" \
		--prefix=/usr --datadir=/usr/share/happy-2.2 || fatal "configure failed"
	runghc Setup.hs build || fatal "build failed"
	test -x "$SRC/dist/build/happy/happy" || fatal "no happy binary produced"
}

recipe_install()
{
	cd "$BUILDDIR/happy-lib"
	runghc Setup.hs copy --destdir="$PKGDEST" || fatal "happy-lib copy failed"
	cd "$SRC"
	runghc Setup.hs copy --destdir="$PKGDEST" || fatal "copy failed"
	"$PKGDEST/usr/bin/happy" --version | grep -q "2.2" ||
		fatal "staged happy is not 2.2"
	printf '{\n%%\n%%%%\n' > "$BUILDDIR/smoke.y"
	"$PKGDEST/usr/bin/happy" -o "$BUILDDIR/smoke.hs" "$BUILDDIR/smoke.y" ||
		fatal "staged happy cannot process a grammar"
}

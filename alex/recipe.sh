#!/bin/sh

# Alex lexical analyser generator (Haskell lex/flex equivalent).
#
# First link of the native Haskell closure: alex + happy are Hadrian
# build prerequisites for ghc, so they are built here with the pinned
# bootstrap GHC bindist (rustc/zig/bun bootstrap.lock pattern: build
# tool only, never shipped). Closure direction:
#   alex, happy (bootstrap GHC) -> ghc (native) -> cabal-install -> stack, hls
#
# The sdist needs no alex/happy to build: src/Parser.y.boot and
# src/Scan.x.boot are the pre-generated sources and the Cabal library
# shipped inside the bootstrap GHC resolves them (standard Hackage
# sdist contract - `cabal install alex` works the same way). Deps are
# boot libraries only (base, array, containers, directory), so the
# classic dependency-free flow applies:
#   runghc Setup.hs configure --prefix + build + copy --destdir
# --datadir is pinned to the FINAL /usr path at configure: the Paths_alex
# module baked into the binary must point at the installed location,
# not staging (same DESTDIR discipline as the bindist installs).

pkgname=alex
pkgver=3.5.4.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Alex lexical analyser generator for Haskell"
license=BSD-3-Clause
origin=alex
repo=saphira
url=https://github.com/haskell/alex
source=https://hackage.haskell.org/package/alex-3.5.4.2/alex-3.5.4.2.tar.gz
sha256=df481dc960e2c59a30395f7335031fd4ef8773b8a42894a4f2320e00ff474418

depends="gmp zlib"
makedepends="
    binutils
    curl
    gcc
"

fatal()
{
	printf 'alex: %s\n' "$1" >&2
	exit 1
}

# Pinned bootstrap GHC (musl bindist, build tool only). Newest alpine
# baseline published for the 9.12 line; the sdist is tested with
# ghc ==9.14.1 and ==9.12.2 per its .cabal, so 9.12.4 is inside the
# supported window.
install_bootstrap_ghc()
{
	expected=$(awk -F'|' '$5 == "ghc-9.12.4-x86_64-alpine3_20-linux.tar.xz" { print $4; exit }' \
		"$RECIPE_DIR/bootstrap.lock")
	test -n "$expected" || fatal "bootstrap archive is not locked"
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
	runghc Setup.hs configure --prefix=/usr \
		--datadir=/usr/share/alex-3.5.4.2 \
		--docdir=/usr/share/doc/alex || fatal "configure failed"
	runghc Setup.hs build || fatal "build failed"
	# Binary smoke against the actual Saphira musl it must run on
	# (the alpine bootstrap runs anywhere; this proof is local).
	# Cabal-library builds land under dist/build (dist-newstyle is
	# cabal-install's directory, not used here).
	test -x "$SRC/dist/build/alex/alex" || fatal "no alex binary produced"
}

recipe_install()
{
	cd "$SRC"
	runghc Setup.hs copy --destdir="$PKGDEST" || fatal "copy failed"
	"$PKGDEST/usr/bin/alex" --version | grep -q "3.5.4.2" ||
		fatal "staged alex is not 3.5.4.2"
	printf '%%{\n%%}\n%%%%\n' > "$BUILDDIR/smoke.x"
	"$PKGDEST/usr/bin/alex" -o "$BUILDDIR/smoke.hs" "$BUILDDIR/smoke.x" ||
		fatal "staged alex cannot process a grammar"
}

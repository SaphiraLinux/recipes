#!/bin/sh

# Haskell Language Server (`haskell-language-server` + wrapper).
#
# 2.15.0.0 is the first HLS with full GHC 9.14.1 support (ORMOLU/
# Fourmolu, case-split/export plugins, semantic tokens by default);
# 2.14.0.0 supported 9.14.1 only basically. Built from the GitHub
# release source with the NATIVE ghc + cabal-install (same shape as
# the stack recipe): Hackage is append-only, so the pinned
# --index-state view keeps resolution reproducible.
#
# The wrapper selects the per-GHC binary at runtime, so both
# executables ship in main. No splits: this is a leaf developer tool.

pkgname=haskell-language-server
pkgver=2.15.0.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Haskell Language Server with wrapper for editors and IDEs"
license=Apache-2.0
origin=haskell-language-server
repo=saphira
url=https://github.com/haskell/haskell-language-server
source=https://github.com/haskell/haskell-language-server/archive/refs/tags/2.15.0.0.tar.gz
sha256=ca5e7637ea62cf8d1223fcba63f64b77924e85ccfb5b716075d030e272f1fbbe

depends="
    ghc
    gmp
    zlib
"
makedepends="
    bash
    binutils
    cabal-install
    curl
    gcc
    ghc
    gmp-dev
    make
    zlib-dev
"

INDEX_STATE=2026-09-04T00:00:00Z

fatal()
{
	printf 'haskell-language-server: %s\n' "$1" >&2
	exit 1
}

recipe_build()
{
	export HOME="$BUILDDIR"
	export CABAL_DIR="$BUILDDIR/cabal-dir"
	export XDG_CACHE_HOME="$BUILDDIR/.cache"
	cd "$SRC"
	cabal update || fatal "cabal update failed"
	cabal install --index-state="$INDEX_STATE" -j"${JOBS:-$(nproc)}" \
		--installdir="$BUILDDIR/bin" --overwrite-policy=always \
		exe:haskell-language-server \
		exe:haskell-language-server-wrapper || fatal "hls build failed"
	for exe in haskell-language-server haskell-language-server-wrapper; do
		test -x "$BUILDDIR/bin/$exe" || fatal "no $exe binary produced"
	done
	"$BUILDDIR/bin/haskell-language-server-wrapper" --version |
		grep -q "2.15.0.0" || fatal "built hls is not 2.15.0.0"
}

recipe_install()
{
	install -D -m0755 "$BUILDDIR/bin/haskell-language-server" \
		"$PKGDEST/usr/bin/haskell-language-server"
	install -D -m0755 "$BUILDDIR/bin/haskell-language-server-wrapper" \
		"$PKGDEST/usr/bin/haskell-language-server-wrapper"
	"$PKGDEST/usr/bin/haskell-language-server-wrapper" --version |
		grep -q "2.15.0.0" || fatal "staged hls is not 2.15.0.0"
}

#!/bin/sh

# Stack: cross-platform Haskell project builder (`stack`).
#
# Built from the GitHub release source with the NATIVE ghc +
# cabal-install (makedepends below): the stack.cabal/cabal.project in
# the tree are the documented distribution-build inputs (Hackage:
# "download the source code from the releases and build it").
# Hackage is append-only, so the pinned --index-state view keeps the
# dependency resolution reproducible (same pin as cabal-install).
#
# Binaries install straight into the package; the Haskell code links
# statically, so no library registration ships. If the builder proves
# a runtime data-file is required, switch to a staged prefix with the
# final datadir baked at configure (alex/happy precedent).

pkgname=stack
pkgver=3.11.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Stack cross-platform program for developing Haskell projects"
license=BSD-3-Clause
origin=stack
repo=saphira
url=https://haskellstack.org/
source=https://github.com/commercialhaskell/stack/archive/refs/tags/v3.11.1.tar.gz
sha256=388916c20e2a9e9d343ef40c0c31fbb664cdbf302122ded8508ded8f765cbb4f

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
	printf 'stack: %s\n' "$1" >&2
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
		exe:stack || fatal "stack build failed"
	test -x "$BUILDDIR/bin/stack" || fatal "no stack binary produced"
	"$BUILDDIR/bin/stack" --version | grep -q "3.11.1" ||
		fatal "built stack is not 3.11.1"
}

recipe_install()
{
	install -D -m0755 "$BUILDDIR/bin/stack" "$PKGDEST/usr/bin/stack"
	"$PKGDEST/usr/bin/stack" --version | grep -q "3.11.1" ||
		fatal "staged stack is not 3.11.1"
}

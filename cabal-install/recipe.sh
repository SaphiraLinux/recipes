#!/bin/sh

# cabal-install: the Cabal/Hackage command-line tool (`cabal`).
#
# Pinned to the 3.16 line to match the Cabal library shipped inside
# ghc-9.14.1 (Cabal-3.16.0.0): the solver still resolves every other
# dependency from Hackage, but the core library interface does not
# skew across the toolchain.
#
# Built from the sdist with a pinned bootstrap `cabal` bindist (musl,
# alpine3_22 - the same libc family as Saphira; go/bun pattern: build
# tool only, never shipped). Hackage is append-only, so the build is
# reproducible through the pinned --index-state view below rather than
# a hand-rolled package list.

pkgname=cabal-install
pkgver=3.16.1.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Cabal package manager command-line tool for Haskell"
license=BSD-3-Clause
origin=cabal-install
repo=saphira
url=https://www.haskell.org/cabal/
source=https://downloads.haskell.org/cabal/cabal-install-3.16.1.0/cabal-install-3.16.1.0.tar.gz
sha256=b03a14e6a56c820b03ad1dd8773ce9bdc87cd8a3b8c8183efd57f1d28d8d8b40

depends="
    ghc
    gmp
    zlib
"
makedepends="
    bash
    binutils
    curl
    gcc
    ghc
    gmp-dev
    make
    zlib-dev
"

# Frozen Hackage view: every input (this sdist excepted) resolves
# inside it. Must postdate all pinned inputs (stack 3.11.1 Jun 2026,
# HLS 2.15.0.0 Sep 2026 share the same pin in their recipes).
INDEX_STATE=2026-09-04T00:00:00Z

fatal()
{
	printf 'cabal-install: %s\n' "$1" >&2
	exit 1
}

install_bootstrap_cabal()
{
	expected=$(awk -F'|' '$5 == "cabal-install-3.16.1.0-x86_64-linux-alpine3_22.tar.xz" { print $4; exit }' \
		"$RECIPE_DIR/bootstrap.lock")
	test -n "$expected" || fatal "bootstrap cabal is not locked"
	curl -fsSL --retry 3 --output "$BUILDDIR/bootstrap-cabal.tar.xz" \
		"https://downloads.haskell.org/cabal/cabal-install-3.16.1.0/cabal-install-3.16.1.0-x86_64-linux-alpine3_22.tar.xz" ||
		fatal "failed to download bootstrap cabal"
	printf '%s  %s\n' "$expected" "$BUILDDIR/bootstrap-cabal.tar.xz" | sha256sum -c - ||
		fatal "bootstrap cabal checksum mismatch"
	mkdir -p "$BUILDDIR/bootcabal"
	tar -xf "$BUILDDIR/bootstrap-cabal.tar.xz" -C "$BUILDDIR/bootcabal"
	boot_cabal=$(find "$BUILDDIR/bootcabal" -name cabal -type f | head -n 1)
	test -n "$boot_cabal" || fatal "bootstrap archive has no cabal binary"
	cp "$boot_cabal" "$BUILDDIR/cabal-boot"
	chmod +x "$BUILDDIR/cabal-boot"
	"$BUILDDIR/cabal-boot" --version | grep -q "3.16.1.0" ||
		fatal "unexpected bootstrap cabal version"
}

recipe_build()
{
	install_bootstrap_cabal
	export PATH="$BUILDDIR:$PATH"
	export HOME="$BUILDDIR"
	export CABAL_DIR="$BUILDDIR/cabal-dir"
	export XDG_CACHE_HOME="$BUILDDIR/.cache"
	cd "$SRC"
	cabal-boot update || fatal "cabal update failed"
	cabal-boot install --index-state="$INDEX_STATE" -j"${JOBS:-$(nproc)}" \
		--installdir="$BUILDDIR/bin" --overwrite-policy=always \
		exe:cabal || fatal "cabal build failed"
	test -x "$BUILDDIR/bin/cabal" || fatal "no cabal binary produced"
	"$BUILDDIR/bin/cabal" --version | grep -q "3.16.1.0" ||
		fatal "built cabal is not 3.16.1.0"
}

recipe_install()
{
	install -D -m0755 "$BUILDDIR/bin/cabal" "$PKGDEST/usr/bin/cabal"
	if [ -f "$SRC/man/cabal.1" ]; then
		install -D -m0644 "$SRC/man/cabal.1" \
			"$PKGDEST/usr/share/man/man1/cabal.1"
	fi
	"$PKGDEST/usr/bin/cabal" --version | grep -q "3.16.1.0" ||
		fatal "staged cabal is not 3.16.1.0"
}

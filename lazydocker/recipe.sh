#!/bin/sh

pkgname=lazydocker
pkgver=0.25.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Terminal UI for Docker (client only)'
license='MIT'
origin=lazydocker
repo=saphira
url=https://github.com/jesseduffield/lazydocker
source=https://github.com/jesseduffield/lazydocker/archive/refs/tags/v${pkgver}.tar.gz
sha256=405071220e5be9aa061c65d290e0347143b73ae0a3cc01df164f0105de2b53c4
# r1: initial native port (terminal client only; talks to the local
# Docker socket at runtime, never serves anything).
# Upstream publishes checksums for release BINARIES only, never for the
# GitHub auto-generated source tarball: the hash above is trust-on-first-
# use, recorded 2026-10-22, and the vendored bytes in files/ are the
# source of truth afterwards. Re-verify out-of-band on every bump.
# Module tree IS vendored upstream (vendor/ + modules.txt): the worker
# builds offline with GOFLAGS=-mod=vendor, GOTOOLCHAIN=local.
# No daemon, no units (client binary only).

depends=""
makedepends="go"

recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/v$pkgver.tar.gz" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/v$pkgver.tar.gz"
	mkdir -p "$BUILDDIR"
	export GOCACHE="$BUILDDIR/.gocache" GOPATH="$BUILDDIR/.gopath"
	export GOFLAGS=-mod=vendor CGO_ENABLED=0 GOTOOLCHAIN=local GOAMD64=v3
	cd "$SRC"
	go build -trimpath \
		-ldflags="-buildid= -s -w -X main.version=v$pkgver -X main.date=2026-04-19" \
		-o "$BUILDDIR/lazydocker" .
	# Proof: --version renders from the stamped variables (flaggy
	# SetVersion), no Docker contact.
	"$BUILDDIR/lazydocker" --version 2>/dev/null | grep -q "$pkgver" ||
		{ echo "ERROR: lazydocker version proof failed" >&2; return 1; }
}

recipe_install()
{
	install -D -m 0755 "$BUILDDIR/lazydocker" "$PKGDEST/usr/bin/lazydocker"
}

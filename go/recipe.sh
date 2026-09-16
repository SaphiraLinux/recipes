#!/bin/sh

pkgname=go
pkgver=1.27.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Go toolchain 1.27.0 (gc, x86-64-v3, musl)"
license=BSD-3-Clause
origin=go
repo=saphira
url=https://go.dev
source=https://go.dev/dl/go1.27.0.src.tar.gz
sha256=7002403d7cc44529ef6d26f69a44818263395ead7c16c05a5808ae047ebeb0e5

# Binary bootstrap for the seed compile (the official linux-amd64
# toolchain - Go builds Go). Hashes are the go.dev-published SHA256
# values for the stable release (dl/?mode=json); the fetch step
# re-verifies both archives, and the VERSION skew check below ties
# the source tree to the same release.
bootstrap_url=https://go.dev/dl/go1.27.0.linux-amd64.tar.gz
bootstrap_sha256=675c26c449cbb18fc24b74650de1eabbae6e16f64326fd85a283fb3b58280685

# Ported from /reference-package-recipes/go (the known-working v0
# bootstrap recipe): same GOAMD64=v3 (matches the
# x86-64-v3 baseline), same GOROOT_FINAL, same CGO posture (proven on
# musl by the old bootstrap). 1.24.11 was the genesis line; 1.27.0
# supersedes it (same-version binary bootstrap, no stepping needed).
# The akadata-era go-1.25.5-r0 in the archive has no
# recipe or provenance and is not followed.
makedepends="
    bash
    gcc
"

recipe_build()
{
	BOOT="$RECIPE_DIR/files/go1.27.0.linux-amd64.tar.gz"
	echo "$bootstrap_sha256  $BOOT" | sha256sum -c - ||
		{ echo "ERROR: Go bootstrap archive missing or corrupt in files/" >&2; return 1; }
	mkdir -p "$BUILDDIR/bootstrap"
	tar -xf "$BOOT" -C "$BUILDDIR/bootstrap"
	cd "$SRC/src"
	GOROOT_BOOTSTRAP="$BUILDDIR/bootstrap/go" GOROOT_FINAL=/usr/lib/go \
		GOOS=linux GOARCH=amd64 GOAMD64=v3 CGO_ENABLED=1 CC=gcc \
		GOFLAGS='-buildvcs=false -trimpath' \
		GOCACHE="$BUILDDIR/.gocache" HOME="$BUILDDIR" \
		CGO_CFLAGS="${CFLAGS-}" CGO_LDFLAGS="${LDFLAGS-}" ./make.bash -v
}

recipe_install()
{
	install -d -m 0755 "$PKGDEST/usr/lib" "$PKGDEST/usr/bin"
	cp -a "$SRC" "$PKGDEST/usr/lib/go"
	rm -rf "$PKGDEST/usr/lib/go/pkg/obj"
	ln -s ../lib/go/bin/go "$PKGDEST/usr/bin/go"
	ln -s ../lib/go/bin/gofmt "$PKGDEST/usr/bin/gofmt"
	# Skew check: the built toolchain must identify as this exact
	# release (catches source/bootstrap mismatch at build time).
	GOROOT="$PKGDEST/usr/lib/go" "$PKGDEST/usr/bin/go" version |
		grep -q "go1.27.0 " ||
		{ echo "ERROR: built toolchain is not go1.27.0" >&2; return 1; }
}

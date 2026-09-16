#!/bin/sh

pkgname=age
pkgver=1.3.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='age file encryption tool (simple, modern, secure)'
license='BSD-3-Clause'
origin=age
repo=saphira
url=https://age-encryption.org/
source=https://github.com/FiloSottile/age/archive/v1.3.1.tar.gz
sha256=396007bc0bc53de253391493bda1252757ba63af1a19db86cfb60a35cb9d290a
# r1: initial native port from reference age (same 1.3.1). Module tree
# is NOT vendored: like breathgslb, the main tarball is pinned and
# modules resolve in the worker (GOFLAGS=-mod=mod, GOCACHE/GOPATH
# under BUILDDIR, GOTOOLCHAIN=local so no toolchain downloads).
# Static musl binaries (CGO_ENABLED=0), no runtime deps.

depends=""
makedepends="go"

recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/v1.3.1.tar.gz" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/v1.3.1.tar.gz"
	mkdir -p "$BUILDDIR"
	export GOCACHE="$BUILDDIR/.gocache" GOPATH="$BUILDDIR/.gopath"
	# GOAMD64=v3 matches the Saphira x86-64-v3 baseline (same as the
	# go toolchain itself and the reference age build); explicit here
	# rather than inherited so the recipe states its floor.
	export GOFLAGS=-mod=mod CGO_ENABLED=0 GOTOOLCHAIN=local GOAMD64=v3
	cd "$SRC"
	for command in age age-keygen age-inspect age-plugin-batchpass; do
		go build -trimpath \
			-ldflags='-buildid= -X main.Version=1.3.1' \
			-o "$BUILDDIR/$command" "./cmd/$command"
	done
}

recipe_install()
{
	for command in age age-keygen age-inspect age-plugin-batchpass; do
		install -D -m 0755 "$BUILDDIR/$command" \
			"$PKGDEST/usr/bin/$command"
	done
}

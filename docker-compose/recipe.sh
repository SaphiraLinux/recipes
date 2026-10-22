#!/bin/sh

pkgname=docker-compose
pkgver=5.6.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Docker Compose plugin (multi-container applications)'
license='Apache-2.0'
origin=docker-compose
repo=saphira
url=https://docs.docker.com/compose/
source=https://github.com/docker/compose/archive/refs/tags/v${pkgver}.tar.gz
sha256=51ad60cc28d38a0850678053f0a259dfee931d150dd1d50ee9e6d758125b1d47
# r1: initial native port (works against docker-engine/cli 29.9.2).
# Static musl binary (CGO_ENABLED=0): no CGO in compose sources (verified).
# Module tree is NOT vendored upstream: like age, modules resolve in the
# worker (GOFLAGS=-mod=mod, GOCACHE/GOPATH under BUILDDIR,
# GOTOOLCHAIN=local so no toolchain downloads).
# GO_BUILDTAGS is forced empty: upstream defaults to `e2e`, which pulls
# test-only code into the binary.
# Installed as a Docker CLI plugin at /usr/lib/docker/cli-plugins/ (the
# system-wide discovery path); `docker compose` resolves it with no
# further configuration.

depends="docker-cli"
makedepends="go"

recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/v$pkgver.tar.gz" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/v$pkgver.tar.gz"
	mkdir -p "$BUILDDIR"
	export GOCACHE="$BUILDDIR/.gocache" GOPATH="$BUILDDIR/.gopath"
	export GOFLAGS=-mod=mod CGO_ENABLED=0 GOTOOLCHAIN=local GOAMD64=v3
	cd "$SRC"
	go build -trimpath -tags "" \
		-ldflags="-buildid= -s -w -X github.com/docker/compose/v5/internal.Version=v$pkgver" \
		-o "$BUILDDIR/docker-compose" ./cmd
	# Proof: version needs no daemon (prints and returns before any client
	# use, verified in cmd/compose/version.go).
	"$BUILDDIR/docker-compose" version --short | grep -q "$pkgver" ||
		{ echo "ERROR: compose version proof failed" >&2; return 1; }
}

recipe_install()
{
	install -D -m 0755 "$BUILDDIR/docker-compose" "$PKGDEST/usr/lib/docker/cli-plugins/docker-compose"
}

#!/bin/sh

pkgname=docker-cli
pkgver=29.9.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Docker CLI client (docker)'
license='Apache-2.0'
origin=docker-cli
repo=saphira
url=https://docs.docker.com/engine/reference/commandline/cli/
source=https://github.com/docker/cli/archive/refs/tags/v${pkgver}.tar.gz
sha256=e3b1fab5e2ee2d6b63b8ce0e8bbd08d6f54c0537c470332f2c345ab997233409
# r1: initial native port (matched to docker-engine 29.9.2).
# Static musl binary (CGO_ENABLED=0): no CGO in cli sources (verified).
# Upstream keeps module metadata in vendor.mod/vendor.sum with symlinks to
# go.mod/go.sum at build time (scripts/with-go-mod.sh); the recipe mirrors
# that here. Modules resolve in the worker for the (small) non-vendored
# remainder? No — vendor/ is complete: GOFLAGS=-mod=vendor.
# No daemon, no init units (client binary only). Man pages omitted in r1
# (need a man generator); noted, not hidden.

depends=""
makedepends="go"

recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/v$pkgver.tar.gz" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/v$pkgver.tar.gz"
	cd "$SRC"
	ln -s vendor.mod go.mod
	ln -s vendor.sum go.sum
	mkdir -p "$BUILDDIR"
	export GOCACHE="$BUILDDIR/.gocache" GOPATH="$BUILDDIR/.gopath"
	export GOFLAGS=-mod=vendor CGO_ENABLED=0 GOTOOLCHAIN=local GOAMD64=v3
	go build -trimpath \
		-ldflags="-buildid= -s -w -X github.com/docker/cli/cli/version.Version=$pkgver -X github.com/docker/cli/cli/version.GitCommit=a82e528901260c8df6073311379eac65f92db204" \
		-o "$BUILDDIR/docker" ./cmd/docker
	# Proof: the client identifies itself (no daemon needed).
	"$BUILDDIR/docker" --version | grep -q "Docker version $pkgver" ||
		{ echo "ERROR: docker version proof failed" >&2; return 1; }
}

recipe_install()
{
	install -D -m 0755 "$BUILDDIR/docker" "$PKGDEST/usr/bin/docker"
}

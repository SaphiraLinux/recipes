#!/bin/sh

pkgname=docker-buildx
pkgver=0.38.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Docker Buildx plugin (extended builds)'
license='Apache-2.0'
origin=docker-buildx
repo=saphira
url=https://docs.docker.com/build/
source=https://github.com/docker/buildx/archive/refs/tags/v${pkgver}.tar.gz
sha256=bfd908c66d13c88cb6dccbc6d0fbb68aab17446901ba24203b5019ebf9d32f67
# r1: initial native port (works against docker-engine/cli 29.9.2).
# Static musl binary (CGO_ENABLED=0): no CGO in buildx sources (verified).
# Vendor tree is shipped (hermetic, no module downloads).
# Installed as a Docker CLI plugin at /usr/lib/docker/cli-plugins/ (the
# system-wide discovery path the official packages use); `docker buildx`
# resolves it with no further configuration.

depends="docker-cli"
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
		-ldflags="-buildid= -s -w -X github.com/docker/buildx/version.Version=v$pkgver -X github.com/docker/buildx/version.Revision=0dbe87f36ed472fe36b6796c3f70b4210a731fc5 -X github.com/docker/buildx/version.Package=github.com/docker/buildx" \
		-o "$BUILDDIR/docker-buildx" ./cmd/buildx
	# Proof: the plugin identifies itself (no daemon needed).
	"$BUILDDIR/docker-buildx" version | grep -q "v$pkgver" ||
		{ echo "ERROR: buildx version proof failed" >&2; return 1; }
}

recipe_install()
{
	install -D -m 0755 "$BUILDDIR/docker-buildx" "$PKGDEST/usr/lib/docker/cli-plugins/docker-buildx"
}

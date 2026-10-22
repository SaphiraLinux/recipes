#!/bin/sh

pkgname=nerdctl
pkgver=2.4.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Docker-compatible CLI for containerd'
license='Apache-2.0'
origin=nerdctl
repo=saphira
url=https://github.com/containerd/nerdctl
source=https://github.com/containerd/nerdctl/archive/refs/tags/v${pkgver}.tar.gz
sha256=ddae9bac35fe8ad35a631d64a179d17589bed3055756f94ef59cf2e0b2a95ee7
# r1: initial native port (matches containerd 2.4.2 per the bundle matrix).
# Static musl binary (CGO_ENABLED=0): no CGO in nerdctl sources (verified).
# Module tree is NOT vendored upstream: like age, modules resolve in the
# worker (GOFLAGS=-mod=mod, GOCACHE/GOPATH under BUILDDIR,
# GOTOOLCHAIN=local so no toolchain downloads).
# depends=containerd (the daemon nerdctl drives). cni-plugins is NOT in
# depends yet — same staged-layering rule as containerd r1: it exists as
# a built package but is not published at the time this recipe is queued;
# without it `nerdctl run` is limited to host/none networking. Documented,
# not hidden.
# No daemon, no init units (client binary only).

depends="containerd"
makedepends="go"

recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/v$pkgver.tar.gz" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/v$pkgver.tar.gz"
	mkdir -p "$BUILDDIR"
	export GOCACHE="$BUILDDIR/.gocache" GOPATH="$BUILDDIR/.gopath"
	export GOFLAGS=-mod=mod CGO_ENABLED=0 GOTOOLCHAIN=local GOAMD64=v3
	cd "$SRC"
	go build -trimpath \
		-ldflags="-buildid= -s -w -X github.com/containerd/nerdctl/v2/pkg/version.Version=$pkgver -X github.com/containerd/nerdctl/v2/pkg/version.Revision=v$pkgver" \
		-o "$BUILDDIR/nerdctl" ./cmd/nerdctl
	# Proof: the binary runs and identifies itself (cobra root --version).
	"$BUILDDIR/nerdctl" --version | grep -q "nerdctl version $pkgver" ||
		{ echo "ERROR: nerdctl version proof failed" >&2; return 1; }
}

recipe_install()
{
	install -D -m 0755 "$BUILDDIR/nerdctl" "$PKGDEST/usr/bin/nerdctl"
}

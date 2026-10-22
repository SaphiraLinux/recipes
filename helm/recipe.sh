#!/bin/sh

pkgname=helm
pkgver=4.3.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Kubernetes package manager (client only)'
license='Apache-2.0'
origin=helm
repo=saphira
url=https://helm.sh/
source=https://github.com/helm/helm/archive/refs/tags/v${pkgver}.tar.gz
sha256=e7b803b6a248c18aea067dbccacaf651c29946db75d05fb23f318ff2f15961c6
# r1: initial native port (client binary only; the operator runs it
# against a cluster, it never serves anything).
# Upstream publishes checksums for release BINARIES only, never for the
# GitHub auto-generated source tarball: the hash above is trust-on-first-
# use, recorded 2026-10-22, and the vendored bytes in files/ are the
# source of truth afterwards. Re-verify out-of-band on every bump.
# Module tree is NOT vendored upstream: like nerdctl, modules resolve in
# the worker (GOFLAGS=-mod=mod, GOCACHE/GOPATH under BUILDDIR,
# GOTOOLCHAIN=local so no toolchain downloads).
# No daemon, no units (client binary only). Cluster access is the
# operator's kubeconfig, never this package.

depends=""
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
		-ldflags="-buildid= -s -w -X helm.sh/helm/v4/internal/version.version=v$pkgver -X helm.sh/helm/v4/internal/version.metadata=" \
		-o "$BUILDDIR/helm" ./cmd/helm
	# Proof: version template renders from the stamped variable only,
	# no cluster contact (verified against pkg/cmd/version.go).
	"$BUILDDIR/helm" version --template '{{.Version}}' | grep -q "v$pkgver" ||
		{ echo "ERROR: helm version proof failed" >&2; return 1; }
}

recipe_install()
{
	install -D -m 0755 "$BUILDDIR/helm" "$PKGDEST/usr/bin/helm"
}

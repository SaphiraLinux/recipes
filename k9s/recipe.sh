#!/bin/sh

pkgname=k9s
pkgver=0.51.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Terminal UI for Kubernetes clusters (client only)'
license='Apache-2.0'
origin=k9s
repo=saphira
url=https://k9scli.io/
source=https://github.com/derailed/k9s/archive/refs/tags/v${pkgver}.tar.gz
sha256=e2c3851c909b87f9cfafa262e426f4a89023ca4e745cba5cab6d0153f76e7dcd
# r1: initial native port (terminal client only; reads the operator's
# kubeconfig, never serves anything).
# Upstream publishes checksums for release BINARIES only, never for the
# GitHub auto-generated source tarball: the hash above is trust-on-first-
# use, recorded 2026-10-22, and the vendored bytes in files/ are the
# source of truth afterwards. Re-verify out-of-band on every bump.
# Module tree is NOT vendored upstream: like nerdctl, modules resolve in
# the worker (GOFLAGS=-mod=mod, GOCACHE/GOPATH under BUILDDIR,
# GOTOOLCHAIN=local so no toolchain downloads).
# No daemon, no units (client binary only).

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
		-ldflags="-buildid= -s -w -X github.com/derailed/k9s/cmd.version=v$pkgver" \
		-o "$BUILDDIR/k9s" .
	# Proof: `version -s` prints the stamped client version and degrades
	# gracefully with no cluster (verified against cmd/version.go).
	"$BUILDDIR/k9s" version -s 2>/dev/null | grep -q "v$pkgver" ||
		{ echo "ERROR: k9s version proof failed" >&2; return 1; }
}

recipe_install()
{
	install -D -m 0755 "$BUILDDIR/k9s" "$PKGDEST/usr/bin/k9s"
}

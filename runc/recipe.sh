#!/bin/sh

pkgname=runc
pkgver=1.5.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='OCI container runtime (opencontainers runc)'
license='Apache-2.0'
origin=runc
repo=saphira
url=https://github.com/opencontainers/runc
source=https://github.com/opencontainers/runc/releases/download/v${pkgver}/runc-${pkgver}.tar.xz
sha256=46eba094e45fc37d96a1b1dc150971fe8d076d6e23bae09dd35443141bed31a1
# r1: initial native port. Pins the stable 1.5.z line (1.6.0 is RC).
# The release tarball carries vendor/ (hermetic Go build, no module
# downloads) and its sha256 is cross-checked against upstream's
# PGP-signed runc.sha256sum for the release.
# CUDA posture: ON but OPTIONAL — the container stack builds GPU
# support as an optional path (nvidia-container-toolkit, Phase 2);
# runc itself has no GPU dependency and works fully without one.
# Build tags are upstream defaults MINUS libpathrs: that tag needs the
# C libpathrs library via pkg-config (not yet a Saphira package), and
# runc explicitly supports dropping it (RUNC_BUILDTAGS=-libpathrs) by
# falling back to the pure-Go pathrs-lite backend (open_purego.go /
# mkdir_purego.go in vendor/). Packaging C libpathrs is r2 follow-up.
# seccomp needs CGO + libseccomp, so the binary links libseccomp
# dynamically (runtime depends below); everything else is vendored Go.

depends="libseccomp"
makedepends="go gcc pkgconf libseccomp-dev"

recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/runc-$pkgver.tar.xz" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/runc-$pkgver.tar.xz"
	mkdir -p "$BUILDDIR"
	export GOCACHE="$BUILDDIR/.gocache" GOPATH="$BUILDDIR/.gopath"
	# GOAMD64=v3 matches the Saphira x86-64-v3 baseline; GOTOOLCHAIN=local
	# so no toolchain downloads; -mod=vendor uses the shipped vendor tree.
	export GOFLAGS=-mod=vendor CGO_ENABLED=1 GOTOOLCHAIN=local GOAMD64=v3
	export CC=gcc
	cd "$SRC"
	go build -trimpath -buildmode=pie \
		-tags 'seccomp urfave_cli_no_docs' \
		-ldflags="-buildid= -X main.gitCommit=v$pkgver" \
		-o "$BUILDDIR/runc" .
	# musl-compat proof: the binary must run and identify itself.
	"$BUILDDIR/runc" --version | grep -q "runc version $pkgver" ||
		{ echo "ERROR: runc version proof failed" >&2; return 1; }
}

recipe_install()
{
	install -D -m 0755 "$BUILDDIR/runc" "$PKGDEST/usr/sbin/runc"
}

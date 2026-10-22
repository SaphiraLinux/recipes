#!/bin/sh

pkgname=crictl
pkgver=1.37.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='CLI for CRI-compatible container runtimes (crictl, matches Kubernetes 1.37)'
license='Apache-2.0'
origin=crictl
repo=saphira
url=https://github.com/kubernetes-sigs/cri-tools
source=https://github.com/kubernetes-sigs/cri-tools/archive/refs/tags/v${pkgver}.tar.gz
sha256=ef81c240412a5b77b164ae6570857b7a0f347770031a697764ba5167389842d8
# r1: initial native port (client binary + default config pointing at
# the local containerd socket). v1.37.0 is the cri-tools release that
# tracks our Kubernetes 1.37 line.
# Upstream publishes checksums for release BINARIES only, never for the
# GitHub auto-generated source tarball: the hash above is trust-on-first-
# use, recorded 2026-10-22, and the vendored bytes in files/ are the
# source of truth afterwards. Re-verify out-of-band on every bump.
# Module tree IS vendored upstream (vendor/ + modules.txt): the worker
# builds offline with GOFLAGS=-mod=vendor, GOTOOLCHAIN=local.
# No daemon, no units (client binary only).

depends="containerd"
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
		-ldflags="-buildid= -s -w -X sigs.k8s.io/cri-tools/pkg/version.Version=v$pkgver" \
		-o "$BUILDDIR/crictl" ./cmd/crictl
	# Proof: --version renders from the stamped variable, no runtime
	# contact.
	"$BUILDDIR/crictl" --version | grep -q "v$pkgver" ||
		{ echo "ERROR: crictl version proof failed" >&2; return 1; }
}

recipe_install()
{
	install -D -m 0755 "$BUILDDIR/crictl" "$PKGDEST/usr/bin/crictl"
	mkdir -p "$PKGDEST/etc"
	printf 'runtime-endpoint: unix:///run/containerd/containerd.sock\nimage-endpoint: unix:///run/containerd/containerd.sock\ntimeout: 10s\ndebug: false\n' \
		> "$PKGDEST/etc/crictl.yaml"
	chmod 0644 "$PKGDEST/etc/crictl.yaml"
}

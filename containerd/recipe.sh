#!/bin/sh

pkgname=containerd
pkgver=2.4.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='containerd container runtime daemon + ctr CLI + runc shim'
license='Apache-2.0'
origin=containerd
repo=saphira
url=https://containerd.io
source=https://github.com/containerd/containerd/archive/refs/tags/v${pkgver}.tar.gz
sha256=02cbbecd0ef78a521d124afa791b843ba5458ef206e1f7f017999ff45c80c0b4
# r1: initial native port (2.4 track, matches nerdctl 2.4.1 bundle matrix).
# CUDA posture: ON but OPTIONAL — GPU access is an additive Phase 2 path;
# the daemon is fully functional without any GPU.
# Static musl binaries (CGO_ENABLED=0). Snapshotter audit: btrfs is
# source-gated on cgo (auto-excluded, no btrfs headers on Saphira);
# devmapper is pure Go (shells out to dmsetup at runtime, harmless
# without it); shipped working set is native + overlayfs (kernel
# overlayfs audited present) + blockfile + erofs. No extra build tags.
# Binaries: containerd, containerd-shim-runc-v2 (execs runc at runtime,
# hence depends), ctr (debug CLI). containerd-stress omitted (test tool).
# CNI plugins are NOT in depends yet — they are the next recipe in the
# chain; without them containers run without pod networking. Documented,
# not hidden.
# Units: OpenRC init.d + systemd unit, both disabled by default.

depends="runc"
makedepends="go"

recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/v$pkgver.tar.gz" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/v$pkgver.tar.gz"
	mkdir -p "$BUILDDIR"
	export GOCACHE="$BUILDDIR/.gocache" GOPATH="$BUILDDIR/.gopath"
	export GOFLAGS=-mod=vendor CGO_ENABLED=0 GOTOOLCHAIN=local GOAMD64=v3
	cd "$SRC"
	VERSION_PKG=github.com/containerd/containerd/v2/version
	LDFLAGS="-buildid= -s -w -X $VERSION_PKG.Version=$pkgver -X $VERSION_PKG.Revision=v$pkgver -X $VERSION_PKG.Package=github.com/containerd/containerd/v2"
	for cmd in containerd ctr containerd-shim-runc-v2; do
		go build -trimpath -ldflags="$LDFLAGS" \
			-o "$BUILDDIR/$cmd" "./cmd/$cmd"
	done
	# Proofs: binaries run and identify themselves (both use the
	# "<name> <package> <version> <revision>" printer).
	"$BUILDDIR/containerd" --version | grep -q "containerd github.com/containerd/containerd/v2 $pkgver" ||
		{ echo "ERROR: containerd version proof failed" >&2; return 1; }
	"$BUILDDIR/ctr" --version | grep -q "ctr github.com/containerd/containerd/v2 $pkgver" ||
		{ echo "ERROR: ctr version proof failed" >&2; return 1; }
	# Default config emitted by the just-built daemon (pure output).
	mkdir -p "$BUILDDIR/etc/containerd"
	"$BUILDDIR/containerd" config default > "$BUILDDIR/etc/containerd/config.toml" ||
		{ echo "ERROR: containerd config default failed" >&2; return 1; }
}

recipe_install()
{
	install -D -m 0755 "$BUILDDIR/containerd" "$PKGDEST/usr/bin/containerd"
	install -D -m 0755 "$BUILDDIR/containerd-shim-runc-v2" "$PKGDEST/usr/bin/containerd-shim-runc-v2"
	install -D -m 0755 "$BUILDDIR/ctr" "$PKGDEST/usr/bin/ctr"
	install -D -m 0644 "$BUILDDIR/etc/containerd/config.toml" "$PKGDEST/etc/containerd/config.toml"
	install -D -m 0755 "$RECIPE_DIR/files/containerd.initd" "$PKGDEST/etc/init.d/containerd"
	install -D -m 0644 "$RECIPE_DIR/files/containerd.service" "$PKGDEST/usr/lib/systemd/system/containerd.service"
}

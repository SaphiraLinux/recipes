#!/bin/sh

pkgname=docker-engine
pkgver=29.9.2
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Docker Engine daemon (dockerd, Moby)'
license='Apache-2.0'
origin=docker-engine
repo=saphira
url=https://docs.docker.com/engine/
source=https://github.com/moby/moby/archive/refs/tags/docker-v${pkgver}.tar.gz
sha256=d7ce182528eb4c182f3884a7a83b7652ffcbc59b21d3d302050564ff949a9689
# r1: initial native port (matched to docker-cli 29.9.2).
# CUDA posture: ON but OPTIONAL — GPU workloads are an additive path via
# the nvidia-container-runtime hook; the daemon is fully functional
# without any GPU.
# Static musl binary (CGO_ENABLED=0) with one first-class tag:
# exclude_graphdriver_btrfs (the btrfs driver imports C unconditionally;
# Saphira has no btrfs headers and overlay2 is the working set anyway).
# Everything else self-configures: journald needs its tag (absent),
# projectquota is cgo-gated (auto-off), nftables falls back to the
# nft-exec backend, zfs driver is pure Go. No extra tags.
# v29 dockerd uses the containerd image store: it REQUIRES the containerd
# socket at runtime (hence depends + After= ordering in both units).
# iptables in depends is deliberate packaging intent: default bridge
# networking is non-functional without it (proven on saphira-test during
# Phase 1: CNI firewall/portmap exec iptables at runtime).
# docker-proxy ships in /usr/libexec/docker (upstream FHS lookup order):
# the daemon refuses to start with userland-proxy enabled when it is
# absent (proven on saphira-test: invalid userland-proxy-path).
# Units: OpenRC init.d + systemd unit, both disabled by default. Adapted
# from upstream contrib/init (direct start, no socket activation;
# /usr/bin + /usr/sbin paths for non-usrmerged Saphira; no firewalld).

depends="containerd iptables"
makedepends="go"

recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/docker-v$pkgver.tar.gz" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/docker-v$pkgver.tar.gz"
	mkdir -p "$BUILDDIR"
	export GOCACHE="$BUILDDIR/.gocache" GOPATH="$BUILDDIR/.gopath"
	export GOFLAGS=-mod=vendor CGO_ENABLED=0 GOTOOLCHAIN=local GOAMD64=v3
	cd "$SRC"
	go build -trimpath -tags exclude_graphdriver_btrfs \
		-ldflags="-buildid= -s -w -X github.com/moby/moby/v2/dockerversion.Version=$pkgver -X github.com/moby/moby/v2/dockerversion.GitCommit=0367cbeb49b9d98cb0b4f51e95f7b54b4803e76c" \
		-o "$BUILDDIR/dockerd" ./cmd/dockerd
	go build -trimpath -tags exclude_graphdriver_btrfs \
		-ldflags="-buildid= -s -w -X github.com/moby/moby/v2/dockerversion.Version=$pkgver -X github.com/moby/moby/v2/dockerversion.GitCommit=0367cbeb49b9d98cb0b4f51e95f7b54b4803e76c" \
		-o "$BUILDDIR/docker-proxy" ./cmd/docker-proxy
	# Proof: the daemon identifies itself (no daemon start needed).
	"$BUILDDIR/dockerd" --version | grep -q "Docker version $pkgver" ||
		{ echo "ERROR: dockerd version proof failed" >&2; return 1; }
	[ -x "$BUILDDIR/docker-proxy" ] ||
		{ echo "ERROR: docker-proxy missing" >&2; return 1; }
}

recipe_install()
{
	install -D -m 0755 "$BUILDDIR/dockerd" "$PKGDEST/usr/bin/dockerd"
	install -D -m 0755 "$BUILDDIR/docker-proxy" "$PKGDEST/usr/libexec/docker/docker-proxy"
	install -D -m 0755 "$RECIPE_DIR/files/dockerd.initd" "$PKGDEST/etc/init.d/dockerd"
	install -D -m 0644 "$RECIPE_DIR/files/dockerd.service" "$PKGDEST/usr/lib/systemd/system/dockerd.service"
}

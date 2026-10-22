#!/bin/sh

pkgname=cni-plugins
pkgver=1.9.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='standard CNI network plugins (bridge, loopback, host-local, portmap, firewall, ...)'
license='Apache-2.0'
origin=cni-plugins
repo=saphira
url=https://www.cni.dev
source=https://github.com/containernetworking/plugins/archive/refs/tags/v${pkgver}.tar.gz
sha256=34bd82d47e981940751619c9cc44c095bb90bfcaf8d71865cbb822c37690a764
# r1: initial native port (matches nerdctl 2.4.1 bundle matrix).
# Static musl binaries (CGO_ENABLED=0): no CGO anywhere in the plugin
# sources (verified). Builds the full upstream set (main + meta +
# ipam, linux only): bridge dummy host-device ipvlan loopback macvlan
# ptp tap vlan bandwidth firewall portmap sbr tuning vrf dhcp
# host-local static.
# Install path /opt/cni/bin is deliberate packaging intent, not upstream
# inertia: it is containerd's compiled-in default bin_dir (our shipped
# config.toml points there), and the path nerdctl/k8s tooling expects.
# firewall/portmap need iptables or nftables at RUNTIME (both are Saphira
# packages, not depends here — same layering rule as the CNI omission in
# containerd r1: no hard dep on an optional backend).
# No daemon, no init units (exec'd by containerd per-pod).

depends=""
makedepends="go"

recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/v$pkgver.tar.gz" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/v$pkgver.tar.gz"
	mkdir -p "$BUILDDIR/bin"
	export GOCACHE="$BUILDDIR/.gocache" GOPATH="$BUILDDIR/.gopath"
	export GOFLAGS=-mod=vendor CGO_ENABLED=0 GOTOOLCHAIN=local GOAMD64=v3
	cd "$SRC"
	for type in main meta ipam; do
		for plugin in plugins/$type/*/; do
			plugin=${plugin%/}; plugin=${plugin##*/}
			case $plugin in windows) continue ;; esac
			go build -trimpath -ldflags='-buildid= -s -w' \
				-o "$BUILDDIR/bin/$plugin" "./plugins/$type/$plugin"
		done
	done
	# Proofs: the three plugins containerd needs most must exist and run.
	for plugin in bridge loopback host-local portmap; do
		[ -x "$BUILDDIR/bin/$plugin" ] ||
			{ echo "ERROR: missing plugin $plugin" >&2; return 1; }
	done
	"$BUILDDIR/bin/bridge" 2>&1 | grep -qi "CNI" ||
		{ echo "ERROR: bridge plugin proof failed" >&2; return 1; }
}

recipe_install()
{
	for bin in "$BUILDDIR"/bin/*; do
		install -D -m 0755 "$bin" "$PKGDEST/opt/cni/bin/${bin##*/}"
	done
}

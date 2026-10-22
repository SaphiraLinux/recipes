#!/bin/sh

pkgname=kubernetes
pkgver=1.37.1
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Kubernetes node components (kubelet, kubeadm, kube-proxy)'
license='Apache-2.0'
origin=kubernetes
repo=saphira
url=https://kubernetes.io
source=https://github.com/kubernetes/kubernetes/archive/refs/tags/v${pkgver}.tar.gz
sha256=89295ac375eb0fdfe68a0696d81be615771d6b27c7ad9bb675dc6ffd0d2ce5f3
# r1: initial native port — the node side of Kubernetes (kubectl ships
# separately and needs no cluster). kubeadm joins/creates clusters;
# kubelet runs pods via CRI (containerd); kube-proxy provides Service
# networking (usually cluster-managed, binary shipped for host use).
# Static musl binaries (CGO_ENABLED=0): no CGO in these trees (verified).
# Vendor tree is shipped (hermetic, no module downloads).
# Version identity via component-base (true v1.37.1 tag commit below).
# Units for kubelet only (the sole host daemon): OpenRC init.d + systemd
# unit, both disabled by default, both honoring /etc/default/kubelet
# (KUBELET_EXTRA_ARGS, the upstream convention kubeadm also writes).
# Plus the upstream kubeadm systemd drop-in
# (kubelet.service.d/10-kubeadm.conf, krel template with
# /etc/sysconfig -> /etc/default adapted): it is SHIPPED BY THIS PACKAGE
# (the kubeadm CLI never touches it) and carries --bootstrap-kubeconfig /
# --kubeconfig / --config plus the runtime kubeadm-flags.env. Without it
# the kubelet starts bare, sees no static manifests, and kubeadm init
# fails at wait-control-plane (observed live 2026-10-21).
# kube-proxy ships binary-only (cluster-managed DaemonSet normally).
# depends: containerd (CRI socket) + cni-plugins (pod networking) +
# kubectl (kubeadm + admin use). socat/ebtables/conntrack, which kubeadm
# preflight may want, are deliberately left out (documented, not hidden).

depends="containerd cni-plugins kubectl"
makedepends="go"

recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/v$pkgver.tar.gz" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/v$pkgver.tar.gz"
	mkdir -p "$BUILDDIR"
	export GOCACHE="$BUILDDIR/.gocache" GOPATH="$BUILDDIR/.gopath"
	export GOFLAGS=-mod=vendor CGO_ENABLED=0 GOTOOLCHAIN=local GOAMD64=v3
	cd "$SRC"
	VERPKG=k8s.io/component-base/version
	COMMIT=f78e722310e50bcaca9276be22276d9e91d91308
	for cmd in kubelet kubeadm kube-proxy; do
		go build -trimpath \
			-ldflags="-buildid= -s -w -X $VERPKG.gitVersion=v$pkgver -X $VERPKG.gitCommit=$COMMIT -X $VERPKG.gitTreeState=clean" \
			-o "$BUILDDIR/$cmd" "./cmd/$cmd"
	done
	# Proofs (no cluster needed): version outputs.
	"$BUILDDIR/kubelet" --version | grep -q "v$pkgver" ||
		{ echo "ERROR: kubelet version proof failed" >&2; return 1; }
	"$BUILDDIR/kubeadm" version -o short | grep -q "v$pkgver" ||
		{ echo "ERROR: kubeadm version proof failed" >&2; return 1; }
	"$BUILDDIR/kube-proxy" --version | grep -q "v$pkgver" ||
		{ echo "ERROR: kube-proxy version proof failed" >&2; return 1; }
}

recipe_install()
{
	install -D -m 0755 "$BUILDDIR/kubelet" "$PKGDEST/usr/bin/kubelet"
	install -D -m 0755 "$BUILDDIR/kubeadm" "$PKGDEST/usr/bin/kubeadm"
	install -D -m 0755 "$BUILDDIR/kube-proxy" "$PKGDEST/usr/bin/kube-proxy"
	install -D -m 0755 "$RECIPE_DIR/files/kubelet.initd" "$PKGDEST/etc/init.d/kubelet"
	install -D -m 0644 "$RECIPE_DIR/files/kubelet.service" "$PKGDEST/usr/lib/systemd/system/kubelet.service"
	# Upstream drop-in: reset+full ExecStart lives here, so the base unit
	# above stays valid standalone (non-kubeadm use) while kubeadm nodes
	# get --kubeconfig/--config/flags.env expansion. Verified byte-shape
	# against the krel template; the $VARS must stay literal in this file.
	install -D -m 0644 "$RECIPE_DIR/files/10-kubeadm.conf" \
		"$PKGDEST/usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf"
}

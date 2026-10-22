#!/bin/sh

pkgname=kubectl
pkgver=0.37.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Kubernetes command-line client (kubectl 1.37 line)'
license='Apache-2.0'
origin=kubectl
repo=saphira
url=https://kubernetes.io/docs/reference/kubectl/
source=https://github.com/kubernetes/kubectl/archive/refs/tags/v${pkgver}.tar.gz
sha256=15632142aa1007a875c3dcde78d5b915348454901b1f85b9cfae7c9c119855a4
# r1: initial native port. Builds the kubectl BINARY from the standalone
# k8s.io/kubectl library module (v0.37.x tracks Kubernetes v1.37.x) plus
# the thin files/kubectl-main.go entrypoint, which is 1:1 equivalent to
# upstream's monorepo cmd wrapper — instead of vendoring the ~150MB
# kubernetes/kubernetes monorepo for one binary.
# Static musl binary (CGO_ENABLED=0): no CGO in kubectl sources (verified).
# No vendor tree: modules resolve in the worker (GOFLAGS=-mod=mod,
# GOCACHE/GOPATH under BUILDDIR, GOTOOLCHAIN=local).
# Version identity comes from client-go's version package (what `kubectl
# version --client` prints): gitVersion v1.37.1 + the true v0.37.1 tag
# commit. No cluster needed for the proof.
# No daemon, no init units (client binary only).

depends=""
makedepends="go"

recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/v$pkgver.tar.gz" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/v$pkgver.tar.gz"
	mkdir -p "$SRC/kubectl-main"
	cp "$RECIPE_DIR/files/kubectl-main.go" "$SRC/kubectl-main/main.go"
	cd "$SRC"
	mkdir -p "$BUILDDIR"
	export GOCACHE="$BUILDDIR/.gocache" GOPATH="$BUILDDIR/.gopath"
	export GOFLAGS=-mod=mod CGO_ENABLED=0 GOTOOLCHAIN=local GOAMD64=v3
# Version identity: `kubectl version --client` prints from
# k8s.io/component-base/version (NOT client-go's copy — verified in
# pkg/cmd/version/version.go). Both are stamped; the component-base one
# is what the proof reads. True v0.37.1 tag commit below. No cluster
# needed for the proof.
CLIENTGO=k8s.io/client-go/pkg/version
COMPBASE=k8s.io/component-base/version
COMMIT=724ca978a8caf483279bf059a294b4a970a2efa1
	go build -trimpath \
		-ldflags="-buildid= -s -w -X $COMPBASE.gitVersion=v1.37.1 -X $COMPBASE.gitCommit=$COMMIT -X $COMPBASE.gitTreeState=clean -X $CLIENTGO.gitVersion=v1.37.1 -X $CLIENTGO.gitCommit=$COMMIT -X $CLIENTGO.gitTreeState=clean" \
		-o "$BUILDDIR/kubectl" ./kubectl-main
	# Proof: client version needs no cluster.
	"$BUILDDIR/kubectl" version --client | grep -q "v1.37.1" ||
		{ echo "ERROR: kubectl version proof failed" >&2; return 1; }
}

recipe_install()
{
	install -D -m 0755 "$BUILDDIR/kubectl" "$PKGDEST/usr/bin/kubectl"
}

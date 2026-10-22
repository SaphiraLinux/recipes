#!/bin/sh

pkgname=headlamp
pkgver=0.46.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Kubernetes web UI deployment manifests (pinned image, ClusterIP, read-only RBAC)'
license='Apache-2.0'
origin=headlamp
repo=saphira
url=https://headlamp.dev/
# r1: artefact package, no compiled code. Upstream publishes no install
# manifest asset for v0.46.0, so the manifests here are adapted from the
# in-repo kubernetes-headlamp.yaml at tag v0.46.0 (vendored verbatim as
# files/upstream-kubernetes-headlamp.yaml with its sidecar; the hash is
# trust-on-first-use, recorded 2026-10-22). Deliberate deviations:
#   - dedicated `headlamp` namespace (upstream uses kube-system: a UI
#     must never share the system namespace, so removal cannot touch it);
#   - image pinned to ghcr.io/headlamp-k8s/headlamp:v0.46.0 (upstream
#     says :latest);
#   - ServiceAccount headlamp-admin bound to the standard `view`
#     ClusterRole (upstream ships a token Secret for an undefined admin
#     account and documents cluster-admin: read-only by default here,
#     escalate explicitly if ever needed);
#   - OTLP/tracing env dropped (no collector on Saphira; re-add with the
#     collector, never against a dead DNS name);
#   - Service is ClusterIP (no public exposure; reach it via
#     kubectl port-forward, never a NodePort/LoadBalancer by default).
# Access token (operator mints, never stored):
#   kubectl -n headlamp create token headlamp-admin
# Removal deletes ONLY the headlamp namespace contents; workloads in
# other namespaces are untouched by construction.

depends=""
makedepends=""

recipe_build()
{
	echo "9a893b6ce1f14660f76c5d79848e64979944125406e762f76278143cd2b863a2  $RECIPE_DIR/files/upstream-kubernetes-headlamp.yaml" | sha256sum -c -
	# The shipped manifests must hold every adaptation above; the build
	# fails if any of them regresses.
	grep -q 'image: ghcr.io/headlamp-k8s/headlamp:v0.46.0' "$RECIPE_DIR/files/deployment.yaml" ||
		{ echo "ERROR: headlamp image pin missing" >&2; return 1; }
	if grep -q ':latest' "$RECIPE_DIR"/files/namespace.yaml "$RECIPE_DIR"/files/serviceaccount.yaml "$RECIPE_DIR"/files/clusterrolebinding.yaml "$RECIPE_DIR"/files/deployment.yaml "$RECIPE_DIR"/files/service.yaml; then
		echo "ERROR: floating image tag in shipped headlamp manifests (the vendored upstream reference keeps its :latest as provenance, it never ships)" >&2; return 1
	fi
	grep -q 'name: headlamp' "$RECIPE_DIR/files/namespace.yaml" ||
		{ echo "ERROR: namespace.yaml does not define headlamp" >&2; return 1; }
	for f in serviceaccount clusterrolebinding deployment service; do
		grep -q 'namespace: headlamp' "$RECIPE_DIR/files/$f.yaml" ||
			{ echo "ERROR: $f.yaml outside headlamp namespace" >&2; return 1; }
	done
	grep -q 'name: view' "$RECIPE_DIR/files/clusterrolebinding.yaml" ||
		{ echo "ERROR: headlamp binding is not read-only view" >&2; return 1; }
	grep -q 'type: ClusterIP' "$RECIPE_DIR/files/service.yaml" ||
		{ echo "ERROR: headlamp Service is not ClusterIP" >&2; return 1; }
	mkdir -p "$BUILDDIR"
}

recipe_install()
{
	for f in namespace serviceaccount clusterrolebinding deployment service; do
		install -D -m 0644 "$RECIPE_DIR/files/$f.yaml" \
			"$PKGDEST/usr/share/headlamp/$f.yaml"
	done
}

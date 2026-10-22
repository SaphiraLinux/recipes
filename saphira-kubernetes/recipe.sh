#!/bin/sh

pkgname=saphira-kubernetes
pkgver=0.1
pkgrel=9
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='native Saphira Kubernetes lifecycle + optional management features'
license='BUSL-1.1'
origin=saphira-kubernetes
repo=saphira
url=https://saphira.vm2.uk/
# r1: initial management package. The tool is a dependency-free shell
# CLI (inventory/plan/apply/verify/drain/uncordon/remove-node/
# remove-cluster) over explicitly authorised SSH hosts plus the
# declarative cluster/node configuration documented in CONFIG.md (the
# same schema saphira-image-creator will consume later). No daemon, no
# units, no service identity: installing this package configures,
# enables and starts nothing.
# r9: optional management features. FEATURES in the cluster config
# declares tooling only (helm/crictl/k9s/headlamp), understood by
# inventory/plan/apply/verify plus features/enable-feature/
# disable-feature verbs; host-scoped portainer status/enable/disable
# for Docker hosts. UI removal never touches workloads, images,
# volumes or cluster configuration. Lifecycle and workloads stay
# separate surfaces.

depends=""
makedepends=""

recipe_build()
{
	# Proof: the CLI parses and its rootless suites pass against the
	# tree sources (fixtures + stub SSH, no network, no root).
	sh -n "$RECIPE_DIR/files/saphira-kubernetes" ||
		{ echo "ERROR: tool syntax check failed" >&2; return 1; }
	sh "$RECIPE_DIR/tests/cli-safety.sh" ||
		{ echo "ERROR: cli-safety suite failed" >&2; return 1; }
	sh "$RECIPE_DIR/tests/determinism.sh" ||
		{ echo "ERROR: determinism suite failed" >&2; return 1; }
	mkdir -p "$BUILDDIR"
}

recipe_install()
{
	install -D -m 0755 "$RECIPE_DIR/files/saphira-kubernetes" \
		"$PKGDEST/usr/sbin/saphira-kubernetes"
	install -D -m 0644 "$RECIPE_DIR/files/CONFIG.md" \
		"$PKGDEST/usr/share/doc/saphira-kubernetes/CONFIG.md"
	install -D -m 0644 "$RECIPE_DIR/files/example-cluster.conf" \
		"$PKGDEST/usr/share/doc/saphira-kubernetes/example-cluster.conf"
	install -D -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-kubernetes/LICENSE"
	# Configuration skeleton only: the hosts file authorises NOBODY
	# until the operator enrols hosts (presence IS the authorisation),
	# and no cluster is defined. Presence here never enables anything
	# anywhere.
	install -d -m 0755 "$PKGDEST/etc/saphira-kubernetes/clusters"
	printf '# saphira-kubernetes hosts: name<TAB>user@host per line.\n# Presence here authorises that host; anything else is refused.\n# Example (commented):\n#\tcp\troot@saphira-test.example\n' \
		> "$PKGDEST/etc/saphira-kubernetes/hosts"
}

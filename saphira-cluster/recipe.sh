#!/bin/sh
# saphira-cluster: native Saphira control utility for Slurm. Discovers
# local capability, applies the service-reservation policy, generates
# and validates Slurm configuration, manages enrolment and reports
# cluster state. It is not a scheduler.
#
# Second product of the Saphira cluster project (Slurm is the first);
# the optional slurm-accounting companion is a third recipe, not a
# third product. AKADATA-owned code, BUSL-1.1 (see LICENCE-summary in
# the project repo; the packaging copy installs below). This licence
# applies to this package only: the Slurm recipes package upstream
# Slurm under GPL-2.0-or-later, and no licence inference crosses that
# boundary.
# Builds from the v0.1.0 tag tarball of the saphira-cluster project
# repo (see files/PROVENANCE.md). No vendored tarball in files/: the
# project repo is the source of truth and the builder fetches +
# verifies the pinned tag archive (verified reachable with plain curl;
# the recipe publishes the APK, never a source archive).

pkgname=saphira-cluster
pkgver=0.1.0
pkgrel=1
# r1: initial packaging. UNBUILT: no builder run yet.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Saphira cluster control utility for Slurm"
license="BUSL-1.1"
origin=saphira-cluster
repo=saphira
url=https://github.com/SaphiraLinux/saphira-cluster
source=https://github.com/SaphiraLinux/saphira-cluster/archive/refs/tags/v0.1.0.tar.gz
sha256=22f1154c1bf0e02aefc6d7fe52a864de234f91bbe51436016f60e6018d9898f1

depends="
    slurm
"

# Hard dependency, deliberately: this is the control layer for Slurm,
# not a standalone inspection tool. Installing saphira-cluster brings
# in the Slurm core it manages. The fact that resources/doctor degrade
# gracefully without Slurm does not redefine the package's purpose.
# No slurm-dev in makedepends: the C does not link the Slurm API. Add
# it if/when Slurm headers/libraries are consumed directly.

makedepends="
    binutils
    gcc
    make
"

subpackages="saphira-cluster-doc"

# Accounting stays optional and separate: slurm-accounting is never a
# dependency here. Operators add `apk add slurm-accounting` only when
# accounting history is wanted.

recipe_build()
{
	# The worker flattens a single top-level archive dir into $SRC,
	# so the tree root lands directly in $SRC.
	cd "$SRC"
	make
	# The CLI harness runs here, in the build: a binary that fails
	# its own tests must not become a package.
	make test
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
	[ -x "$PKGDEST/usr/sbin/saphira-cluster" ] || \
		{ echo "ERROR: saphira-cluster payload is missing the binary" >&2; return 1; }
	[ -e "$PKGDEST/usr/share/man/man8/saphira-cluster.8" ] || \
		{ echo "ERROR: saphira-cluster payload is missing the man page" >&2; return 1; }
	# Shipped licence text (packaging derivative of the canonical
	# LICENCE-summary.txt in the project repo) and provenance record.
	install -D -m 0644 "$RECIPE_DIR/files/LICENCE-summary.txt" \
		"$PKGDEST/usr/share/licenses/saphira-cluster/LICENSE.txt"
	install -D -m 0644 "$RECIPE_DIR/files/PROVENANCE.md" \
		"$PKGDEST/usr/share/doc/saphira-cluster/PROVENANCE.md"
}

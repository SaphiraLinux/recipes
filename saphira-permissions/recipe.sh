#!/bin/sh

pkgname=saphira-permissions
pkgver=0.1
pkgrel=3
# r3: --root accepts empty as live (ensure-caps,
# ensure-permissions); orchestrator distinguishes child failure
# (exit 2) from drift (exit 1): a dead child suppresses the normal
# summary with a failure banner and exits 2, apply records the
# child exit code. Payload change, revision bumps.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Saphira system metadata reconciliation (declared filesystem ownership, modes, capabilities)"
license="BUSL-1.1"
origin=saphira-permissions
repo=saphira
url=https://saphira.vm2.uk/

# Local source (no upstream): payload lives in files/ (reconciler
# tools + architecture documentation), all Saphira-original under
# BUSL-1.1. Initial publication is r1: no r0 packages, ever.

depends="
	saphira-baselayout
	bash
	coreutils
	libcap
	mawk
"
makedepends=""

# r2: co-owned claims collapse (whole-line uniqueness: every
# package ships var/log, so the same claim repeated N times
# reported N drifts); differing claims for one path survive and
# warn as packaging conflicts (converged deterministically in byte
# order, reported honestly every check). Symlink handling is
# lstat-authoritative (recorded-777 link skips silently, genuine
# 777 files converge). Payload change, revision bumps.
# r1: V1 (permissions slice): ensure-caps (caps.d fragment
# reconciler: file capabilities, the metadata class APK cannot
# represent), ensure-permissions (explicit full-system
# audit/recovery over the installed closure: installed-DB claims
# plus per-package fragment orchestration plus the undeclared-cap
# sweep), the administrator override directory skeleton, and the
# architecture document reserving the future access-model names
# (documentation only, nothing parsed).

recipe_build()
{
	# No build step: shell tools ship verbatim from files/.
	:
}

recipe_install()
{
	install -D -m 0755 "$RECIPE_DIR/files/libexec/ensure-caps" \
		"$PKGDEST/usr/libexec/saphira/ensure-caps"
	install -D -m 0755 "$RECIPE_DIR/files/libexec/ensure-permissions" \
		"$PKGDEST/usr/libexec/saphira/ensure-permissions"
	# Administrator override directory (empty skeleton): operator
	# files placed here are /etc config (apk-protected across
	# upgrades); no package payload may ever populate it.
	install -d -m 0755 "$PKGDEST/etc/saphira/permissions/override.d"
	install -D -m 0644 "$RECIPE_DIR/files/DESIGN.md" \
		"$PKGDEST/usr/share/doc/saphira-permissions/DESIGN.md"
	install -D -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-permissions/LICENSE"
}

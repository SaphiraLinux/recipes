pkgname=saphira-packager
pkgver=1.0
# r50: provider selection matches exact package names (a -dev/-doc NVR
# must never satisfy a base-name dependency during declaration
# extraction); viewer conflicts output names its legacy-pair semantics.
# r51: republish without the stale usr/share/man/man8/saphira-build.8
# (canonical home is saphira-docs since the man-hierarchy move; the
# published r50 artifact predates it). Recipe install set unchanged
# since r50 - this revision exists to unblock the file-ownership gate.
# r57: file-ownership stanza (file <path> <mode> <owner> <group>) in
# account fragments: makepkg validates shape plus payload binding,
# the publish gate enforces same-fragment-or-root references, and the
# generated install scripts apply ownership through ensure-identity
# (baselayout r12 carries the reconciler side).
# r58: legacy-history sidecars (<fragment>.legacy): makepkg validates
# shape plus same-fragment consistency, the publish gate refuses
# legacy IDs colliding with any present, census skips sidecars.
# r59: buildpkg is authoritative over stale environments: the base
# rebuilds automatically on live seed NVR drift (presence-based
# per-NVR rule, multi-line coexistence is not drift), clean roots
# provision a locked root shadow row (base schema v2), and retained
# FAILED workspaces from a stale base generation move aside with
# logs intact while a fresh workspace executes.
# r60: sign-apk-repo --full-audit heals with an empty stage (census
# rebuild of indexes + repository.db from disk truth, no publish,
# no retention); empty stage without the flag stays a refusal.
# r61: sysusers-native fragments (makepkg sysusers stanza, generated
# reconciler-then-systemd-sysusers callers, bootstrap tolerates
# identity-less fragments) plus the legacy-gate namespace fix: a
# legacy user's primary GID is a reference, not a group-namespace
# history claim, so paired user+group sidecars publish.
pkgrel=66
# r66: caps.d file-capability declarations (saphira-permissions V1):
# makepkg validates the fragment (known capability names, same
# payload target, no strays/duplicates), generates
# ensure-identity -> ensure-fhs -> ensure-caps callers, adds the
# saphira-permissions+libcap ordering deps, and records the receipt
# caps key; the publish gate enforces the selective
# ships-fragment<->declares coherence (no ledger change: the
# same-payload-target rule plus the file gate guarantee one package
# per capped path). Must be installed before alfred r3 /
# breathgslb r3 build, so the new gate actually guards those
# builds. Payload change, revision bumps.
# r65: makepkg refuses payload files/dirs beneath usr/etc, usr/var,
# usr/com (autoconf prefix-default leaks: proftpd /usr/var, lynx
# /usr/etc incidents) unless covered by an explicit reviewed
# LAYOUT_ALLOW entry (owner-bound, exact paths). Must be installed
# before proftpd r5 / lynx r2 build, so the new gate actually guards
# those builds. + seed assembly runs --no-scripts with explicit fhs.d
# convergence and a fail-closed guard (virgin roots cannot satisfy
# script interpreters/helpers mid-order; first proven by baselayout
# r17 breaking canonical base assembly). Payload change,
# revision bumps.
# Provenance (configure-layout sweep, 6e2f9ef): the ~170 recipe
# hygiene edits (explicit --prefix/--sysconfdir/--localstatedir) are
# NEXT-build policy only. No mass rebuild at existing NVRs: those
# published NVRs were NOT built from the new recipe text, and the
# immutable-NVR gate will force the normal pkgrel bump if any such
# package is ever rebuilt with changed bytes. No mass pkgrel bump.
# r64: repo_db.py fhs_claims keeps one row per exact path (a fragment
# legitimately describes the same path as both dir and
# replace-symlink-dir; the ledger tracks ownership per path, so the
# second claim violated the fhs_paths PRIMARY KEY and failed
# baselayout r17 publication) + extract_declarations installs each
# carrier closure in its own isolated root (the archive keeps retired
# generations with mutually exclusive pins; one shared root either
# refuses or silently attributes the newest payload's census to older
# NVRs, which broke full-audit reconciliation). Payload change,
# revision bumps.
# r62: saphira-build OpenRC pidfile /run/saphira-build.pid ->
# /var/run/saphira-build.pid (flat, tracked-only payload file;
# no builder/controller logic touched).
# r63: repo_db.py additive-schema self-heal (live DBs predate
# fhs_paths) + sysusers-native declared counting (guarantees both
# in the published controller library regardless of what r62
# captured). Payload change, revision bumps.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Native Saphira package builder tools'
license=BUSL-1.1
origin=saphira-packager
repo=saphira
url=https://saphira.vm2.uk/

depends="
	fakeroot
	python3
	sqlite
"

recipe_build()
{
	:
}

recipe_install()
{
	install -d "$DESTDIR/usr/bin" "$DESTDIR/etc/saphira"
	install -m 755 "$RECIPE_DIR/files/buildpkg" "$DESTDIR/usr/bin/buildpkg"
	install -m 755 "$RECIPE_DIR/files/buildpkg-single" "$DESTDIR/usr/bin/buildpkg-single"
	install -m 755 "$RECIPE_DIR/files/makepkg" "$DESTDIR/usr/bin/makepkg"
	install -m 755 "$RECIPE_DIR/files/checkpkg" "$DESTDIR/usr/bin/checkpkg"
	install -m 755 "$RECIPE_DIR/files/installpkg" "$DESTDIR/usr/bin/installpkg"
	install -m 755 "$RECIPE_DIR/files/cleanpkg" "$DESTDIR/usr/bin/cleanpkg"
	install -m 755 "$RECIPE_DIR/files/resolvepkg" "$DESTDIR/usr/bin/resolvepkg"
	install -m 755 "$RECIPE_DIR/files/sign-apk-repo" "$DESTDIR/usr/bin/sign-apk-repo"
	install -m 755 "$RECIPE_DIR/files/promote-repo" "$DESTDIR/usr/bin/promote-repo"
	install -d "$DESTDIR/usr/lib/saphira-packager"
	install -m 644 "$RECIPE_DIR/files/repo-index.sh" "$DESTDIR/usr/lib/saphira-packager/repo-index.sh"
	install -m 644 "$RECIPE_DIR/files/repo_db.py" "$DESTDIR/usr/lib/saphira-packager/repo_db.py"
	install -m 755 "$RECIPE_DIR/files/saphira-repo-migrate" "$DESTDIR/usr/bin/saphira-repo-migrate"
	install -m 755 "$RECIPE_DIR/files/saphira-repo-state" "$DESTDIR/usr/bin/saphira-repo-state"
	install -m 755 "$RECIPE_DIR/files/seed-repo" "$DESTDIR/usr/bin/seed-repo"
	install -m 755 "$RECIPE_DIR/files/bumppkg" "$DESTDIR/usr/bin/bumppkg"
	install -m 755 "$RECIPE_DIR/files/saphira-build" "$DESTDIR/usr/bin/saphira-build"
	# The bootstrap exception ships too: once this package is
	# installed, controller refreshes come from the installed copy
	# (siblings resolved beside it in /usr/bin), never from tree
	# paths. buildsign rides along: the refresh script expects it
	# as a source and the payload lacked it identically.
	install -m 755 "$RECIPE_DIR/files/install-saphira-packager" "$DESTDIR/usr/bin/install-saphira-packager"
	install -m 755 "$RECIPE_DIR/files/buildsign" "$DESTDIR/usr/bin/buildsign"
	install -m 644 "$RECIPE_DIR/files/package_builder.sh" "$DESTDIR/etc/saphira/package_builder.sh"
	install -m 644 "$RECIPE_DIR/files/version-lines.conf" "$DESTDIR/etc/saphira/version-lines.conf"
	# Autobuilder service: dual init formats, per house convention.
	install -d "$DESTDIR/etc/conf.d" "$DESTDIR/etc/init.d" "$DESTDIR/usr/lib/systemd/system"
	install -m 755 "$RECIPE_DIR/files/saphira-build.initd" "$DESTDIR/etc/init.d/saphira-build"
	install -m 644 "$RECIPE_DIR/files/saphira-build.confd" "$DESTDIR/etc/conf.d/saphira-build"
	install -m 644 "$RECIPE_DIR/files/saphira-build.service" "$DESTDIR/usr/lib/systemd/system/saphira-build.service"
	install -D -m 644 "$RECIPE_DIR/files/LICENSE" "$DESTDIR/usr/share/licenses/saphira-packager/LICENSE"
}

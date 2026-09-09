pkgname=saphira-packager
pkgver=1.0
# r50: provider selection matches exact package names (a -dev/-doc NVR
# must never satisfy a base-name dependency during declaration
# extraction); viewer conflicts output names its legacy-pair semantics.
pkgrel=50
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

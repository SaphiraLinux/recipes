pkgname=saphira-packager
pkgver=1.0
pkgrel=41
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
	install -m 755 "$RECIPE_DIR/files/seed-repo" "$DESTDIR/usr/bin/seed-repo"
	install -m 755 "$RECIPE_DIR/files/bumppkg" "$DESTDIR/usr/bin/bumppkg"
	install -m 755 "$RECIPE_DIR/files/saphira-build" "$DESTDIR/usr/bin/saphira-build"
	install -m 644 "$RECIPE_DIR/files/package_builder.sh" "$DESTDIR/etc/saphira/package_builder.sh"
	install -m 644 "$RECIPE_DIR/files/bootstrap-v0.1.paths" "$DESTDIR/etc/saphira/bootstrap-v0.1.paths"
	install -m 644 "$RECIPE_DIR/files/version-lines.conf" "$DESTDIR/etc/saphira/version-lines.conf"
	# Autobuilder service: dual init formats, per house convention.
	install -d "$DESTDIR/etc/conf.d" "$DESTDIR/etc/init.d" "$DESTDIR/usr/lib/systemd/system"
	install -m 755 "$RECIPE_DIR/files/saphira-build.initd" "$DESTDIR/etc/init.d/saphira-build"
	install -m 644 "$RECIPE_DIR/files/saphira-build.confd" "$DESTDIR/etc/conf.d/saphira-build"
	install -m 644 "$RECIPE_DIR/files/saphira-build.service" "$DESTDIR/usr/lib/systemd/system/saphira-build.service"
	install -D -m 644 "$RECIPE_DIR/files/LICENSE" "$DESTDIR/usr/share/licenses/saphira-packager/LICENSE"
}

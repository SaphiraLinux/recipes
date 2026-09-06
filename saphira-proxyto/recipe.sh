#!/bin/sh

pkgname=saphira-proxyto
pkgver=0.1.0
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='PROXY-protocol front proxy for non-aware applications (geomyidae)'
license='BUSL-1.1'
origin=saphira-proxyto
repo=saphira
url=https://saphira.vm2.uk/
# Local source (no upstream, no git yet): payload lives in files/
# (single-file C service, man page, instance configs).

depends=""
makedepends="
	gcc
	make
"
subpackages="$pkgname-doc"

recipe_build()
{
	# Local source builds out-of-tree so files/ stays pristine.
	rm -rf "$BUILDDIR/build"
	mkdir -p "$BUILDDIR/build"
	cp -r "$RECIPE_DIR/files/Makefile" "$RECIPE_DIR/files/src" "$BUILDDIR/build/"
	# Saphira baseline per target arch (x86-64-v3 today; extend here
	# when new SAPHIRA_ARCH values land - fail closed otherwise).
	case "${SAPHIRA_ARCH:-x86_64}" in
		x86_64) march=x86-64-v3 ;;
		aarch64) march=armv8-a ;;
		*) echo "ERROR: unsupported SAPHIRA_ARCH for saphira-proxyto: ${SAPHIRA_ARCH:-x86_64}" >&2; return 1 ;;
	esac
	make -C "$BUILDDIR/build" -j${JOBS:-$(nproc)} CC=gcc ARCH="$march" PREFIX=/usr
	# Upstream tests bind loopback sockets; the build sandbox may not
	# provide them, so they run on the test deployment, not here.
}

recipe_install()
{
	install -D -m 0755 "$BUILDDIR/build/proxyto" "$PKGDEST/usr/bin/proxyto"
	install -D -m 0644 "$RECIPE_DIR/files/man/proxyto.1" "$PKGDEST/usr/share/man/man1/proxyto.1"
	install -D -m 0644 "$RECIPE_DIR/files/etc/saphira/proxyto/geomyidae.conf" \
		"$PKGDEST/etc/saphira/proxyto/geomyidae.conf"
	install -D -m 0755 "$RECIPE_DIR/files/proxyto.initd" \
		"$PKGDEST/etc/init.d/proxyto"
	install -D -m 0644 "$RECIPE_DIR/files/proxyto.confd" \
		"$PKGDEST/etc/conf.d/proxyto"
	install -D -m 0644 "$RECIPE_DIR/files/proxyto.service" \
		"$PKGDEST/usr/lib/systemd/system/proxyto.service"
	install -D -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-proxyto/LICENSE"
}

#!/bin/sh

pkgname=saphira-gredist
pkgver=0.1.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Protocol 47/GRE distributor with HRW backend selection'
license='MIT'
origin=saphira-gredist
repo=saphira
url=https://saphira.vm2.uk/
# Local source (no upstream, no git yet): payload lives in files/
# (C11 control service + gre-sink/gre-send lab tools, man page,
# example config, lab harness). Kernel reference files ip_gre.c /
# ip6_gre.c at the recipe root are reference only, never built.

depends="iputils"
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
		*) echo "ERROR: unsupported SAPHIRA_ARCH for saphira-gredist: ${SAPHIRA_ARCH:-x86_64}" >&2; return 1 ;;
	esac
	make -C "$BUILDDIR/build" -j${JOBS:-$(nproc)} CC=gcc ARCH="$march" PREFIX=/usr
	# Upstream tests need raw sockets, netns and OVS; the build
	# sandbox provides none, so they run on the lab, not here.
}

recipe_install()
{
	install -D -m 0755 "$BUILDDIR/build/src/gredist" "$PKGDEST/usr/bin/gredist"
	install -D -m 0755 "$BUILDDIR/build/src/gre-sink" "$PKGDEST/usr/bin/gre-sink"
	install -D -m 0755 "$BUILDDIR/build/src/gre-send" "$PKGDEST/usr/bin/gre-send"
	install -D -m 0644 "$RECIPE_DIR/files/man/gredist.1" \
		"$PKGDEST/usr/share/man/man1/gredist.1"
	install -D -m 0644 "$RECIPE_DIR/files/etc/saphira/gredist/example.conf" \
		"$PKGDEST/etc/saphira/gredist/example.conf"
	install -D -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-gredist/LICENSE"
	install -D -m 0755 "$RECIPE_DIR/files/tests/lab.sh" \
		"$PKGDEST/usr/share/saphira-gredist/lab.sh"
	install -D -m 0755 "$RECIPE_DIR/files/tests/run-tests.sh" \
		"$PKGDEST/usr/share/saphira-gredist/run-tests.sh"
}

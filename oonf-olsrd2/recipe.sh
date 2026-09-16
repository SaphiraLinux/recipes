#!/bin/sh

pkgname=oonf-olsrd2
pkgver=0.15.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='OLSRv2 routing agent (OONF OLSR.org Network Framework)'
license='BSD-3-Clause'
origin=oonf-olsrd2
repo=saphira
url=https://github.com/OLSR/OONF
source=https://github.com/OLSR/OONF/archive/refs/tags/v0.15.1.tar.gz
sha256=9e25331fed34c2319defa29f19252b4871650c291cb97f1be067ba631e6c8b00

# Recon verdict (2026-09-10): upstream master is 187 commits ahead of the
# v0.15.1 tag, but the drift is routine maintenance (docs, DLEP fixes,
# debugging) with no rewrite or API break. Saphira pins the stable tag:
# reproducible release artifact over a moving target. Re-evaluate master
# only if the tag proves deficient (a pinned commit hash would then be
# the reproducible form, never a floating branch).
# Privilege model (verified in src/olsrd2/CMakeLists.txt): OONF_NEED_ROOT
# is true - olsrd2 refuses to run without root (route/netlink control).
# No service identity applies; both service units run it as root.
# Crypto plugins stay off exactly as upstream ships them (commented out
# in src-plugins/CMakeLists.txt), so no libtomcrypt dependency exists.
# libuci/OpenWrt plugins are not built (Saphira is not OpenWrt).
makedepends="
    cmake
    gcc
    libnl-dev
    make
    ninja
    pkgconf
"

recipe_build()
{
	cmake -S "$SRC" -B "$BUILDDIR" \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DOONF_VERSION=0.15.1 \
		-DOONF_LIB_GIT=v0.15.1
	cmake --build "$BUILDDIR" -j${JOBS:-$(nproc)}
}

recipe_install()
{
	DESTDIR="$PKGDEST" cmake --build "$BUILDDIR" --target install_olsrd2
	# Upstream ships a commented interface-template config; install it
	# as the starting point (the admin names the mesh interfaces).
	install -D -m 0644 "$SRC/src/olsrd2/debian/olsrd2.conf" \
		"$PKGDEST/etc/olsrd2/olsrd2.conf"
	install -D -m 0755 "$RECIPE_DIR/files/olsrd2.initd" \
		"$PKGDEST/etc/init.d/olsrd2"
	install -D -m 0644 "$RECIPE_DIR/files/olsrd2.service" \
		"$PKGDEST/usr/lib/systemd/system/olsrd2.service"
}

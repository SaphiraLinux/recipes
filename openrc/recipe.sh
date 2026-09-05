#!/bin/sh

pkgname=openrc
pkgver=0.62.1
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="OpenRC init system: dependency-based service management"
license="BSD-2-Clause"
origin=openrc
repo=main
url=https://github.com/OpenRC/openrc
source=https://github.com/OpenRC/openrc/archive/refs/tags/${pkgver}.tar.gz
sha256=935014044b5704b4f4e2f8b2b5faf4d1a3597f925a8a204a7a6d050060f5dcc4

depends="
    saphira-baselayout
"

makedepends="
    gcc
    libcap-dev
    saphira-kernel-headers=7.1.5
    meson
    ninja
    pkgconf
"

recipe_build()
{
	meson setup build "$SRC" \
		--bindir=/bin --sbindir=/sbin --libdir=/lib \
		--libexecdir=/lib --buildtype=release \
		-Dos=Linux -Daudit=disabled -Dselinux=disabled -Dpam=false \
		-Dnewnet=false -Dsysvinit=true -Dbash-completions=true \
		-Dzsh-completions=false -Dpkgconfig=true -Dshell=/bin/bash
	ninja -C build
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C build install
	# Saphira platform boot services, moved out of the init-neutral
	# baselayout so removing this package removes every OpenRC trace.
	install -d -m 0755 "$PKGDEST/etc/init.d" "$PKGDEST/etc/conf.d"
	install -m 0755 "$RECIPE_DIR/files/openrc-boot/saphira-boot-ok" \
		"$PKGDEST/etc/init.d/saphira-boot-ok"
	install -m 0755 "$RECIPE_DIR/files/openrc-boot/net-online" \
		"$PKGDEST/etc/init.d/net-online"
	install -m 0755 "$RECIPE_DIR/files/openrc-boot/network.initd" \
		"$PKGDEST/etc/init.d/network"
	install -m 0644 "$RECIPE_DIR/files/openrc-boot/confd-network" \
		"$PKGDEST/etc/conf.d/network"
}

#!/bin/sh

pkgname=udev
pkgver=261.2
pkgrel=4
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Standalone systemd udev device manager"
license="LGPL-2.1-or-later"
origin=udev
repo=main
url=https://systemd.io/
source=https://github.com/systemd/systemd/archive/refs/tags/v261.2.tar.gz
sha256=ed1059ff964f5df35b6056434cc17cc83f86dc913f10489948a0b19b6081c5ec

depends="
    kmod
    libucontext
"

makedepends="
    acl-dev
    gcc
    binutils
    gawk
    gperf
    kmod-dev
    libcap-dev
    libucontext-dev
    saphira-kernel-headers=7.1.5
    make
    meson
    ninja
    pkgconf
    python-jinja2
    util-linux-dev
"

subpackages="
    $pkgname-dev
"

recipe_build()
{
	meson setup "$BUILDDIR" "$SRC" \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--buildtype=release \
		-Dlibc=musl \
		-Dinitrd=false \
		-Dhibernate=false \
		-Dpam=disabled \
		-Dacl=enabled \
		-Dadm-group=false \
		-Danalyze=false \
		-Dapparmor=disabled \
		-Daudit=disabled \
		-Dbacklight=false \
		-Dbinfmt=false \
		-Dbootloader=disabled \
		-Dbpf-framework=disabled \
		-Ddbus=disabled \
		-Dcoredump=false \
		-Defi=false \
		-Denvironment-d=false \
		-Dgcrypt=disabled \
		-Dgnutls=disabled \
		-Dhostnamed=false \
		-Dkernel-install=false \
		-Dlibcryptsetup=disabled \
		-Dlibcurl=disabled \
		-Dlibfido2=disabled \
		-Dlibidn2=disabled \
		-Dlogind=false \
		-Dnetworkd=false \
		-Dopenssl=disabled \
		-Dp11kit=disabled \
		-Dpolkit=disabled \
		-Dqrencode=disabled \
		-Dresolve=false \
		-Dseccomp=disabled \
		-Dselinux=disabled \
		-Dsysusers=false \
		-Dtimesyncd=false \
		-Dtmpfiles=false \
		-Dtpm=false \
		-Dukify=disabled \
		-Dutmp=false \
		-Dvconsole=false \
		-Dxkbcommon=disabled \
		-Dhwdb=true \
		-Dman=disabled \
		-Dstandalone-binaries=true \
		-Dstatic-libudev=true \
		-Dtests=false \
		-Dlink-udev-shared=false \
		-Dsplit-bin=false \
		-Dsysvinit-path= \
		-Drpmmacrosdir=no \
		-Dpamconfdir=no
	ninja -C "$BUILDDIR"
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install

	# Reduce the staged tree to exactly the shared device-manager payload:
	# udevadm, the standalone daemon, hwdb, rules and libudev.  Everything
	# else the source builds belongs to the systemd package; the whitelist
	# keeps that boundary explicit as upstream layout moves.
	kept="$PKGDEST.keep"
	mkdir "$kept"
	for item in \
		bin/udevadm \
		usr/bin/udevadm \
		usr/bin/systemd-hwdb \
		lib/systemd/systemd-udevd \
		lib/udev \
		etc/udev \
		usr/lib/libudev.so* \
		usr/lib/libudev.a \
		usr/include/libudev.h \
		usr/lib/pkgconfig/libudev.pc \
		usr/share/pkgconfig/udev.pc
	do
		for src in "$PKGDEST"/$item; do
			if [ -e "$src" ] || [ -L "$src" ]; then
				dest=$kept/${src#"$PKGDEST"/}
				mkdir -p "$(dirname "$dest")"
				cp -a "$src" "$dest"
			fi
		done
	done
	rm -rf -- "$PKGDEST"
	mv "$kept" "$PKGDEST"
}

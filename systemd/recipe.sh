#!/bin/sh

pkgname=systemd
pkgver=261.2
pkgrel=4
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="System and service manager"
license="LGPL-2.1-or-later"
origin=systemd
repo=main
url=https://systemd.io/
source=https://github.com/systemd/systemd/archive/refs/tags/v261.2.tar.gz
sha256=ed1059ff964f5df35b6056434cc17cc83f86dc913f10489948a0b19b6081c5ec

# udev owns the shared device-manager payload; this package is its strict
# complement and always runs alongside it.
depends="
    kmod
    libucontext
    udev
"

makedepends="
    acl-dev
    binutils
    curl-dev
    gcc
    gawk
    gperf
    kmod-dev
    libarchive-dev
    libseccomp-dev
    libucontext-dev
    saphira-kernel-headers=7.1.5
    lz4-dev
    make
    meson
    ninja
    openssl-dev
    pcre2-dev
    pkgconf
    python-jinja2
    python-pefile
    util-linux-dev
    zstd-dev
"

recipe_build()
{
	# Feature policy: intended features are enabled explicitly with their
	# dependencies declared in makedepends, never left to environment-
	# dependent auto-detection.
	meson setup "$BUILDDIR" "$SRC" \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--buildtype=release \
		-Dlibc=musl \
		-Dacl=enabled \
		-Dblkid=enabled \
		-Dhibernate=true \
		-Dinitrd=true \
		-Dlibcurl=enabled \
		-Dlz4=enabled \
		-Dopenssl=enabled \
		-Dseccomp=enabled \
		-Dxz=disabled \
		-Dzstd=enabled \
		-Dtests=false \
		-Dman=disabled \
		-Dpam=disabled

	# Explicit non-default states and their recorded reasons:
	#   xz=disabled   queued: repository xz lacks a -dev split (port next).
	#   man=disabled  queued: python3 packaging lacks dev headers; chain is
	#                 python3-dev -> python-lxml -> re-enable man and docs.
	#   pam=disabled  queued: linux-pam port chain (flex, bison, gettext,
	#                 libtirpc) not yet packaged.
	#   tests=false   payload-only build: the test suite pulls additional
	#                 introspection dependencies and ships nothing.
	# initrd/hibernate are intentional Saphira states (true): both are
	# dependency-free upstream booleans kept on deliberately.
	ninja -C "$BUILDDIR"
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install

	# Strict-complement rule: remove exactly the paths owned by the shared
	# udev package so no file is ever duplicated between the two.  Keep this
	# list mirroring the udev recipe whitelist; units under
	# /usr/lib/systemd stay here even when they reference the udev daemon.
	for path in \
		bin/udevadm \
		usr/bin/udevadm \
		usr/bin/systemd-hwdb \
		lib/systemd/systemd-udevd \
		lib/udev \
		etc/udev \
		usr/include/libudev.h \
		usr/lib/libudev.a \
		usr/lib/libudev.so \
		usr/lib/libudev.so.1 \
		usr/lib/libudev.so.1.7.14 \
		usr/lib/pkgconfig/libudev.pc \
		usr/share/pkgconfig/udev.pc; do
		rm -rf -- "$PKGDEST"/$path
	done
}

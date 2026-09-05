#!/bin/sh

pkgname=gettext
pkgver=0.23.2
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="GNU internationalisation library and toolset"
license="GPL-3.0-or-later LGPL-2.1-or-later"
origin=gettext
repo=main
url=https://www.gnu.org/software/gettext/
source=https://ftp.gnu.org/gnu/gettext/gettext-0.23.2.tar.xz
sha256=86bec63472ae1e7a18871758a1358a9e9776f74643992a0276dd67e36de2da7d

depends=""

makedepends="
    binutils
    gcc
    gawk
    make
"

subpackages="gettext-dev gettext-doc"
recipe_build()
{
	# Proven v0 flags: NLS enabled, JVM/C# runtimes off.
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--disable-java \
		--disable-csharp \
		--disable-libasprintf \
		--enable-threads=posix
	make
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}

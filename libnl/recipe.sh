pkgname=libnl
pkgver=3.11.0
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Netlink protocol library suite'
license='LGPL-2.1-or-later'
origin=libnl
repo=main
url=https://github.com/thom311/libnl
source=https://github.com/thom311/libnl/releases/download/libnl3_11_0/libnl-3.11.0.tar.gz
sha256=2a56e1edefa3e68a7c00879496736fdbf62fc94ed3232c0baba127ecfa76874d

makedepends="
	binutils
	bison
	flex
	gawk
	gcc
	saphira-kernel-headers=7.1.5
	m4
	make
	pkgconf
"

subpackages="libnl-dev libnl-doc"
recipe_build()
{
	./configure --prefix=/usr --sysconfdir=/etc --disable-static --disable-cli
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}

pkgname=nettle
pkgver=3.10.2
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Low-level cryptographic library (gnutls dependency)'
license='LGPL-3.0-or-later OR GPL-2.0-or-later'
origin=nettle
repo=main

subpackages="nettle-dev"
url=https://www.lysator.liu.se/~nisse/nettle/
source=https://ftp.gnu.org/gnu/nettle/nettle-3.10.2.tar.gz
sha256=fe9ff51cb1f2abb5e65a6b8c10a92da0ab5ab6eaf26e7fc2b675c45f1fb519b5

makedepends="
	m4
	binutils
	gawk
	gcc
	make
"

# v0-proven flags: --disable-documentation (no texinfo on Saphira)
recipe_build()
{
	./configure --prefix=/usr --disable-static --disable-documentation \
		--disable-dependency-tracking
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}

pkgname=libtasn1
pkgver=4.19.0
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='ASN.1 structure parser library (gnutls dependency)'
license='LGPL-2.1-or-later'
origin=libtasn1
repo=main
url=https://www.gnutls.org/
source=https://ftp.gnu.org/gnu/libtasn1/libtasn1-4.19.0.tar.gz
sha256=1613f0ac1cf484d6ec0ce3b8c06d56263cc7242f1c23b30d82d23de345a63f7a

makedepends="
	binutils
	gawk
	gcc
	make
"

subpackages="$pkgname-dev"

recipe_build()
{
	./configure --prefix=/usr --disable-static --disable-doc --disable-dependency-tracking
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}

pkgname=libretls
pkgver=3.8.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='libtls API implementation on top of OpenSSL'
license='ISC'
origin=libretls
repo=saphira
url=https://git.causal.agency/libretls/
source=https://causal.agency/libretls/libretls-${pkgver}.tar.gz
sha256=3bc9fc0e61827ee2f608e5e44993a8fda6d610b80a1e01a9c75610cc292997b5

depends="openssl"
makedepends="
	gcc
	make
	pkgconf
	openssl-dev
"
subpackages="$pkgname-dev"

recipe_build() {
	./configure --prefix=/usr --disable-static
	make -j${JOBS:-$(nproc)}
}

recipe_install() {
	make DESTDIR="$PKGDEST" install
	find "$PKGDEST" -name '*.la' -delete
}

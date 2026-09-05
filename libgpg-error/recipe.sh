pkgname=libgpg-error
pkgver=1.61
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Support library for libgcrypt and GnuPG components'
license='GPL-2.0-or-later'
origin=libgpg-error
repo=saphira
url=https://www.gnupg.org/software/libgpg-error/
source=https://www.gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-${pkgver}.tar.bz2
sha256=7a85413f2bc354f4f8aa832b718af122e48965e9e0eb9012ee659c13c6385c93

subpackages="$pkgname-dev $pkgname-doc"
makedepends="gcc make pkgconf gawk"

recipe_build() {
	./configure --prefix=/usr --disable-nls --disable-rpath
	make -j${JOBS:-$(nproc)}
}

recipe_install() {
	make DESTDIR="$PKGDEST" install
}

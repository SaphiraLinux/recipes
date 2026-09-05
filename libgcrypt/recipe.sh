pkgname=libgcrypt
pkgver=1.11.2
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='General purpose crypto library based on the code from GnuPG'
license='LGPL-2.1-or-later'
origin=libgcrypt
repo=saphira
url=https://www.gnupg.org/software/libgcrypt/
source=https://www.gnupg.org/ftp/gcrypt/libgcrypt/libgcrypt-${pkgver}.tar.bz2
sha256=6ba59dd192270e8c1d22ddb41a07d95dcdbc1f0fb02d03c4b54b235814330aac

depends="libgpg-error"
subpackages="$pkgname-dev $pkgname-doc"
makedepends="gcc make pkgconf gawk libgpg-error-dev"

recipe_build() {
	./configure --prefix=/usr --disable-rpath --disable-asm
	make -j${JOBS:-$(nproc)}
}

recipe_install() {
	make DESTDIR="$PKGDEST" install
}

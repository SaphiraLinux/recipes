pkgname=libseccomp
pkgver=2.6.1
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='High level interface to the Linux kernel syscall filtering'
license='LGPL-2.1-or-later'
origin=libseccomp
repo=saphira
url=https://github.com/seccomp/libseccomp
source=https://github.com/seccomp/libseccomp/releases/download/v${pkgver}/libseccomp-${pkgver}.tar.gz
sha256=501f66c667225d53791b97e1d7cf85ab764c297d04881f60f38f451c4b0ee1be

makedepends="gcc make pkgconf gawk gperf"
subpackages="$pkgname-dev $pkgname-doc"

recipe_build() {
	./configure --prefix=/usr --disable-python
	make -j${JOBS:-$(nproc)}
}

recipe_install() {
	make DESTDIR="$PKGDEST" install
}

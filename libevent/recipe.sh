pkgname=libevent
pkgver=2.1.12
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Event notification library (async DNS, HTTP, RPC)'
license='BSD-3-Clause'
origin=libevent
repo=main
url=https://libevent.org/
source=https://github.com/libevent/libevent/releases/download/release-2.1.12-stable/libevent-2.1.12-stable.tar.gz
sha256=92e6de1be9ec176428fd2367677e61ceffc2ee1cb119035037a27d346b0403bb

depends="openssl"
makedepends="gcc make openssl-dev pkgconf"
subpackages="$pkgname-dev"

recipe_build() {
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	"$SRC/configure" \
		--prefix=/usr \
		--libdir=/usr/lib \
		--disable-static \
		--enable-openssl
	make -j${JOBS:-$(nproc)}
}

recipe_install() {
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
}

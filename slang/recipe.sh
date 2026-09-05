pkgname=slang
pkgver=2.3.3
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='S-Lang programming library (terminal handling, text interpretation)'
license='GPL-2.0-or-later'
origin=slang
repo=main
url=https://www.jedsoft.org/slang/
# Pinned to the BLFS conglomeration mirror: jedsoft.org rate-limits
# automated fetches; bytes are the upstream 2.3.3 release tarball.
source=https://ftp.osuosl.org/pub/blfs/conglomeration/slang/slang-${pkgver}.tar.bz2
sha256=f9145054ae131973c61208ea82486d5dd10e3c5cdad23b7c4a0617743c8f5a18

depends="ncurses"
makedepends="gcc make ncurses-dev pkgconf"
subpackages="$pkgname-dev $pkgname-doc"

recipe_build() {
	./configure --prefix=/usr --libdir=/usr/lib --sysconfdir=/etc \
		--with-pkgconfigdir=/usr/lib/pkgconfig \
		--with-terminfo=default --without-pcre --without-onig \
		--without-png --without-readline
	make -j${JOBS:-$(nproc)}
}

recipe_install() {
	make DESTDIR="$PKGDEST" install
}

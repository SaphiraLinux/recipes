pkgname=joe
pkgver=4.6
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Full featured terminal-based screen editor'
license='GPL-2.0-or-later'
origin=joe
repo=saphira
url=https://joe-editor.sourceforge.io/
source=https://downloads.sourceforge.net/project/joe-editor/JOE%20sources/joe-${pkgver}/joe-${pkgver}.tar.gz
sha256=495a0a61f26404070fe8a719d80406dc7f337623788e445b92a9f6de512ab9de

depends="ncurses"
makedepends="gcc make pkgconf gawk ncurses-dev"

recipe_build() {
	./configure --prefix=/usr --sysconfdir=/etc
	make -j${JOBS:-$(nproc)}
}

recipe_install() {
	make DESTDIR="$PKGDEST" install
}

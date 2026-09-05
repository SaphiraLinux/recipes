#!/bin/sh

pkgname=vim
pkgver=9.1.0880
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Vi Improved editor'
license='Vim'
origin=vim
repo=saphira
url=https://www.vim.org/
source=https://github.com/vim/vim/archive/refs/tags/v${pkgver}.tar.gz
sha256=011d2653dffbd74239794348fdd01d67fcdaddb55c27f7b706f4cc00a3b16f22

depends="ncurses"
makedepends="gcc make pkgconf ncurses-dev"

subpackages="$pkgname-doc"

recipe_build()
{
	cd "$SRC"
	./configure --prefix=/usr --with-features=normal --enable-multibyte \
		--enable-gui=no --without-x --disable-gpm \
		--disable-netbeans --with-tlib=ncursesw
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
}

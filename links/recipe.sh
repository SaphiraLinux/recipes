#!/bin/sh

pkgname=links
pkgver=2.30
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Twibright Links: text-mode web browser"
license="GPL-2.0-or-later"
origin=links
repo=saphira
url=https://links.twibright.com/
source=http://links.twibright.com/download/links-2.30.tar.bz2
sha256=c4631c6b5a11527cdc3cb7872fc23b7f2b25c2b021d596be410dadb40315f166

makedepends="
    binutils
    gcc
    make
    openssl-dev
    zlib-dev
"

# --disable-graphics --without-x: text-mode build; no X/GUI recipes.
recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	"$SRC/configure" --prefix=/usr --disable-graphics --without-x \
		--with-ssl --with-zlib
	make
}

recipe_install()
{
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
}

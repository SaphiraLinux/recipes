#!/bin/sh

pkgname=jq
pkgver=1.8.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Lightweight and flexible command-line JSON processor"
license="MIT"
origin=jq
repo=saphira
url=https://jqlang.github.io/jq/
source=https://github.com/jqlang/jq/releases/download/jq-1.8.2/jq-1.8.2.tar.gz
sha256=71b8d6e8f5fe81f6c6d0d110e3892251f6ce76ed095abd315e26e6e1193af3af

makedepends="
    binutils
    gcc
    make
    oniguruma-dev
"

recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	"$SRC/configure" --prefix=/usr --with-oniguruma
	make
}

recipe_install()
{
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
}

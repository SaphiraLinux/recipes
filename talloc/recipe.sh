#!/bin/sh
pkgname=talloc
pkgver=2.4.4
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Hierarchical, reference counted memory pool system'
license='GPL-3.0-or-later OR LGPL-3.0-or-later'
origin=talloc
repo=saphira
url=https://talloc.samba.org/
talloc_sha256=55e47994018c13743485544e7206780ffbb3c8495e704a99636503e6e77abf59
depends=""
makedepends="gawk gcc make pkgconf python3"
subpackages="$pkgname-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/talloc-2.4.4.tar.gz"
	cd "$SRC"
	echo "$talloc_sha256  $RECIPE_DIR/files/talloc-2.4.4.tar.gz" | sha256sum -c -
	./configure --prefix=/usr --disable-python
	make -j${JOBS:-$(nproc)} PYTHON=python3 WAF_BIN="$SRC/buildtools/bin/waf"
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install PYTHON=python3 WAF_BIN="$SRC/buildtools/bin/waf"
}

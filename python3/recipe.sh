#!/bin/sh
pkgname=python3
pkgver=3.14.6
pkgrel=10
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Python 3.14 interpreter (Genesis base, system install, no venv)'
license='PSF-2.0'
origin=python3
repo=saphira
url=https://www.python.org/
python3_sha256=143b1dddefaec3bd2e21e3b839b34a2b7fb9842272883c576420d605e9f30c63
depends="musl bzip2 xz zlib openssl libffi ncurses readline sqlite"
makedepends="
	bzip2-dev
	gcc
	gawk
	libffi-dev
	saphira-kernel-headers=7.1.5
	make
	ncurses-dev
	openssl-dev
	pkgconf
	readline-dev
	sqlite-dev
	xz-dev
	zlib-dev
"
subpackages="$pkgname-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/Python-3.14.6.tar.xz"
	cd "$SRC"
	echo "$python3_sha256  $RECIPE_DIR/files/Python-3.14.6.tar.xz" | sha256sum -c -
	# ensurepip off: CPython bundles a pip wheel and 'make install' would
	# seed /usr/bin/pip3 + site-packages/pip, colliding with python3-pip
	# (which owns those files). Consumers add python3-pip explicitly.
	./configure --prefix=/usr \
		--enable-shared \
		--with-ensurepip=no \
		--with-system-ffi \
		--disable-test-modules \
		ac_cv_buggy_getaddrinfo=no \
		ac_cv_file__dev_ptmx=yes \
		ac_cv_file__dev_ptc=no
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
	ln -sf python3 "$PKGDEST/usr/bin/python"
}

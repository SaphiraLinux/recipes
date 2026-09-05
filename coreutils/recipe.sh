#!/bin/sh

pkgname=coreutils
pkgver=9.7
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='GNU core utilities (Genesis base, /bin layout)'
license='GPL-3.0-or-later'
origin=coreutils
repo=saphira
url=https://www.gnu.org/software/coreutils/
# Vendored: https://ftp.gnu.org/gnu/coreutils/coreutils-9.7.tar.xz
coreutils_sha256=e8bb26ad0293f9b5a1fc43fb42ba970e312c66ce92c1b0b16713d7500db251bf

depends="musl"
makedepends="
	gawk
	gcc
	gmp-dev
	make
"

# /bin placement matches the stage4-era payload (Saphira non-usrmerged).
# No man pages v1 (help2man chain not packaged); --disable-nls.
recipe_build()
{
	CUBALL="$RECIPE_DIR/files/coreutils-9.7.tar.xz"
	echo "$coreutils_sha256  $CUBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$CUBALL"
	cd "$SRC"
	export FORCE_UNSAFE_CONFIGURE=1
	./configure --prefix=/usr \
		--bindir=/bin \
		--enable-install-program=arch,hostname \
		--disable-nls \
		--disable-libcap \
		--without-openssl \
		--without-libcrypto \
		DEFAULT_POSIX2_COMPAT=ENABLE
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
	# GNU release tarballs ship pre-built man/info pages; the recipe-level
	# rule is that documentation lives in per-package -doc splits, and
	# procps-ng-doc owns uptime(1)'s man page. Strip the doc trees.
	rm -rf "$PKGDEST/usr/share/man" "$PKGDEST/usr/share/info"
}

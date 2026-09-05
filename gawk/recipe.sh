#!/bin/sh
pkgname=gawk
pkgver=5.3.2
pkgrel=5
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='GNU awk pattern scanning and processing language'
license='GPL-3.0-or-later'
origin=gawk
repo=saphira
url=https://www.gnu.org/software/gawk/
gawk_sha256=f8c3486509de705192138b00ef2c00bbbdd0e84c30d5c07d23fc73a9dc4cc9cc
depends="gmp mpfr"
makedepends="gawk gcc gmp-dev make mpfr-dev readline-dev"
subpackages="$pkgname-dev $pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/gawk-5.3.2.tar.xz"
	cd "$SRC"
	echo "$gawk_sha256  $RECIPE_DIR/files/gawk-5.3.2.tar.xz" | sha256sum -c -
	AWK=/usr/bin/mawk ./configure --prefix=/usr --sysconfdir=/etc --disable-nls --without-readline
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
	# mawk owns /usr/bin/awk (the small default awk). GNU gawk's install
	# creates the awk symlink unconditionally; drop it so both awks can
	# coexist. gawk is invoked by name, and POSIX scripts get mawk.
	rm -f "$PKGDEST/usr/bin/awk"
}

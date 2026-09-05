#!/bin/sh

pkgname=libargon2
pkgver=20190702
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Argon2 password-hashing function (argon2id reference implementation)'
license='CC0-1.0'
origin=libargon2
repo=saphira
url=https://github.com/P-H-C/phc-winner-argon2
source=https://github.com/P-H-C/phc-winner-argon2/archive/20190702.tar.gz
sha256=daf972a89577f8772602bf2eb38b6a3dd3d922bf5724d45e7f9589b5e830442c

# Consumers: php85 --with-password-argon2 (password_hash ARGON2ID).
depends=""
makedepends="
	gcc
	make
"
subpackages="$pkgname-dev"

recipe_build() {
	make -j${JOBS:-$(nproc)} \
		OPTTARGET=generic \
		PREFIX=/usr \
		LIBRARY_REL=lib \
		PKGCONFIG_REL=lib/pkgconfig
}

recipe_install() {
	# The upstream Makefile defaults the Linux-x86_64 library path to the
	# Debian multiarch dir; Saphira is plain /usr/lib.  The ?= assignments
	# above accept these overrides.
	make install \
		OPTTARGET=generic \
		PREFIX=/usr \
		LIBRARY_REL=lib \
		PKGCONFIG_REL=lib/pkgconfig \
		DESTDIR="$PKGDEST"
	rm -f "$PKGDEST/usr/lib/libargon2.a"
	install -d -m 0755 "$PKGDEST/usr/share/licenses/libargon2"
	install -m 0644 "$SRC/LICENSE" "$PKGDEST/usr/share/licenses/libargon2/LICENSE"
}

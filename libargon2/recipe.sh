#!/bin/sh

pkgname=libargon2
pkgver=20190702
pkgrel=2
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
recipe_build()
{
	make -j${JOBS:-$(nproc)} \
		OPTTARGET=generic \
		PREFIX=/usr \
		LIBRARY_REL=lib \
		PKGCONFIG_REL=lib
}

recipe_install() {
	# Upstream defaults the Linux-x86_64 library path to the Debian
	# multiarch dir; Saphira is plain /usr/lib, hence LIBRARY_REL. But
	# PKGCONFIG_REL is NOT the full relative dir - upstream appends
	# /pkgconfig itself (INST_PKGCONFIG = PREFIX/PKGCONFIG_REL +
	# /pkgconfig), so lib/pkgconfig here doubled to
	# /usr/lib/pkgconfig/pkgconfig/ and pkg-config never saw the file
	# (broke php85 configure). Plain lib lands it at /usr/lib/pkgconfig.
	make install \
		OPTTARGET=generic \
		PREFIX=/usr \
		LIBRARY_REL=lib \
		PKGCONFIG_REL=lib \
		DESTDIR="$PKGDEST"
	rm -f "$PKGDEST/usr/lib/libargon2.a"
	install -d -m 0755 "$PKGDEST/usr/share/licenses/libargon2"
	install -m 0644 "$SRC/LICENSE" "$PKGDEST/usr/share/licenses/libargon2/LICENSE"
}

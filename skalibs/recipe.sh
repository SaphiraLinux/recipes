#!/bin/sh

pkgname=skalibs
pkgver=2.15.1.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Skarnet general-purpose C library (utmps build requirement)"
license='ISC'
origin=skalibs
repo=saphira
url=https://skarnet.org/software/skalibs/
source=https://skarnet.org/software/skalibs/skalibs-2.15.1.0.tar.gz
sha256=f9c905e74935c6fe911c7e344e3e89d5fbd2014c1a04650b524b15ce9b5635d1

depends=""

makedepends="
    binutils
    gcc
    make
"

subpackages="skalibs-dev"

# Standard skarnet build: ./configure && make && make install.
# No slashpackage, no TAI clock (Saphira runs UTC/NTP like the rest
# of the world), IPv6 kept. Static and shared libraries both build
# by default; the -dev split owns headers and the static archive
# per the standard split rules. No .pc files (upstream default off;
# utmps finds skalibs via its sysdeps dir, not pkg-config).
# utmps (the first consumer) needs >= 2.15.1.0; pin the floor, not
# the ceiling, so compatible rebuilds do not force restarts here.
recipe_build()
{
	cd "$SRC" && ./configure \
		--prefix=/usr \
		--libdir=/usr/lib
	make
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
	install -D -m 0644 "$SRC/COPYING" \
		"$PKGDEST/usr/share/licenses/skalibs/COPYING"
	[ -e "$PKGDEST"/usr/lib/libskarnet.so* ] ||
	[ -e "$PKGDEST"/usr/lib/libskarnet.a ] || {
		echo "ERROR: skalibs payload has no libskarnet" >&2
		return 1
	}
}

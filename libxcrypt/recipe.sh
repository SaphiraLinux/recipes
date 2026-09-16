#!/bin/sh

pkgname=libxcrypt
pkgver=4.4.38
# r2: Saphira crypt policy. musl owns the system crypt namespace
# (<crypt.h>, generic -lcrypt); libxcrypt is optional extended
# functionality selected explicitly. No glibc-compat default: musl
# already provides encrypt/setkey, and no consumer needs obsolete
# glibc-era symbols (verified: Egg's running libcrypt.so.2 carries
# none). Runtime libcrypt.so.2 stays global for existing binaries.
# r3: manual pages follow the same ownership: man-pages owns the
# generic crypt.3/crypt_r.3; libxcrypt-doc keeps the extended API
# pages (gensalt/ra/rn, checksalt, preferred_method, crypt.5) only.
# Supersedes unpublished r2 (payload delta: minus two doc files).
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Extended crypt library for password hashing (libcrypt)"
license="LGPL-2.1-or-later"
origin=libxcrypt
repo=main
url=https://github.com/besser82/libxcrypt
source=https://github.com/besser82/libxcrypt/releases/download/v4.4.38/libxcrypt-4.4.38.tar.xz
sha256=80304b9c306ea799327f01d9a7549bdb28317789182631f1b54f4511b4206dd6

depends=""
makedepends="
    binutils
    gcc
    make
    gawk
    perl
"

subpackages="$pkgname-dev libxcrypt-doc"

recipe_build()
{
	# No glibc obsolete-API compat surface: musl is the system libc
	# authority; libxcrypt ships the extended implementation only.
	# SONAME stays libcrypt.so.2 (verified XCRYPT_2.0 floor), so
	# already-linked binaries keep running.
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--disable-static \
		--enable-obsolete-api=no \
		--disable-failure-tokens
	make
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	# Private development namespace: the header and the -lcrypt dev
	# link move out of the global paths so generic <crypt.h>/-lcrypt
	# resolve to musl. Runtime libcrypt.so.2 stays global.
	mkdir -p "$PKGDEST/usr/include/libxcrypt" "$PKGDEST/usr/lib/libxcrypt"
	mv "$PKGDEST/usr/include/crypt.h" "$PKGDEST/usr/include/libxcrypt/crypt.h"
	rm -f "$PKGDEST/usr/lib/libcrypt.so"
	ln -s ../libcrypt.so.2 "$PKGDEST/usr/lib/libxcrypt/libcrypt.so"
	# The explicit interface is pkg-config libxcrypt; the global
	# libcrypt.pc masquerades as the default provider (nothing in
	# /recipes consumes it - verified 2026-09-16) and goes.
	sed -i \
		-e 's|^Cflags:.*|Cflags: -I${includedir}/libxcrypt|' \
		-e 's|^Libs:.*|Libs: -L${libdir}/libxcrypt -lcrypt|' \
		"$PKGDEST/usr/lib/pkgconfig/libxcrypt.pc"
	rm -f "$PKGDEST/usr/lib/pkgconfig/libcrypt.pc"
	# Generic crypt manuals belong to man-pages (verified complete
	# overlap census 2026-09-16: only crypt.3 + crypt_r.3 collide;
	# the 8 extended pages are unique to libxcrypt-doc and stay).
	rm -f "$PKGDEST/usr/share/man/man3/crypt.3" \
		"$PKGDEST/usr/share/man/man3/crypt_r.3"
	# Ownership asserts: musl alone owns the global crypt namespace.
	test ! -e "$PKGDEST/usr/include/crypt.h" || {
		echo "ERROR: global crypt.h still staged" >&2; return 1; }
	test ! -e "$PKGDEST/usr/lib/libcrypt.so" || {
		echo "ERROR: global libcrypt.so still staged" >&2; return 1; }
	test ! -e "$PKGDEST/usr/lib/pkgconfig/libcrypt.pc" || {
		echo "ERROR: global libcrypt.pc still staged" >&2; return 1; }
	test ! -e "$PKGDEST/usr/share/man/man3/crypt.3" || {
		echo "ERROR: generic crypt.3 still staged (man-pages owns it)" >&2; return 1; }
	test ! -e "$PKGDEST/usr/share/man/man3/crypt_r.3" || {
		echo "ERROR: generic crypt_r.3 still staged (man-pages owns it)" >&2; return 1; }
	test -f "$PKGDEST/usr/share/man/man3/crypt_gensalt.3" || {
		echo "ERROR: extended crypt_gensalt.3 missing" >&2; return 1; }
	test -f "$PKGDEST/usr/include/libxcrypt/crypt.h" || {
		echo "ERROR: private crypt.h missing" >&2; return 1; }
	test -L "$PKGDEST/usr/lib/libxcrypt/libcrypt.so" || {
		echo "ERROR: private libcrypt.so link missing" >&2; return 1; }
	grep -q -- "-I\${includedir}/libxcrypt" \
		"$PKGDEST/usr/lib/pkgconfig/libxcrypt.pc" || {
		echo "ERROR: libxcrypt.pc lacks private includedir" >&2; return 1; }
	grep -q -- "-L\${libdir}/libxcrypt" \
		"$PKGDEST/usr/lib/pkgconfig/libxcrypt.pc" || {
		echo "ERROR: libxcrypt.pc lacks private libdir" >&2; return 1; }
	grep -q crypt_gensalt "$PKGDEST/usr/include/libxcrypt/crypt.h" || {
		echo "ERROR: private crypt.h lacks extended API" >&2; return 1; }
}

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
pkgrel=7
# r6: the generic crypt namespace belongs to musl, and stays musl's.
# musl-dev owns an EMPTY libcrypt.a for build-system compatibility and
# crypt()/crypt_r() live in musl's libc, so an ordinary -lcrypt resolves
# crypt() out of libc. libxcrypt therefore ships NO generic libcrypt.so and
# NO real generic libcrypt.a; what it adds is libxcrypt.so, its own link
# name, so a consumer can opt into yescrypt deliberately instead of by
# accident. libxcrypt.pc names it.
#
# r4 and r5 each got this wrong in opposite directions and are superseded:
# r4 re-exposed libxcrypt's implementation as the generic libcrypt.so, and
# r5 invented a linker-script shim that was redundant with the empty archive
# musl already provides. Neither was needed.
# r7: FHS non-usrmerged — /bin/login, passwd, su, getsubids +
# /sbin/sulogin link libcrypt, so the runtime SONAME chain ships in
# /lib (verified 2026-10-19 via ldd). Dev/opt-in names stay in
# /usr/lib as absolute /lib targets (development artefacts, not
# usrmerge; no relative ../ links). Egg carries an unowned stage1
# fossil in /lib; the package must stage it in /lib.
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
	# FHS non-usrmerged: /bin/login, passwd, su, getsubids +
	# /sbin/sulogin link libcrypt, so the runtime SONAME chain ships
	# in /lib; dev/opt-in names stay in /usr/lib as absolute /lib
	# targets (no relative ../ links).
	mkdir -p "$PKGDEST/lib"
	for lib in "$PKGDEST/usr/lib/libcrypt.so.2"*; do
		[ -e "$lib" ] && mv "$lib" "$PKGDEST/lib/"
	done
	# Private development namespace: the header and the -lcrypt dev
	# link move out of the global paths so generic <crypt.h>/-lcrypt
	# resolve to musl. Runtime libcrypt.so.2 stays global.
	mkdir -p "$PKGDEST/usr/include/libxcrypt" "$PKGDEST/usr/lib/libxcrypt"
	mv "$PKGDEST/usr/include/crypt.h" "$PKGDEST/usr/include/libxcrypt/crypt.h"
	rm -f "$PKGDEST/usr/lib/libcrypt.so"
	# The generic -lcrypt name is musl's, and it is not this package's to
	# provide. musl ships an EMPTY libcrypt.a for build-system
	# compatibility (musl-dev owns it; verified 8 bytes, no members), and
	# crypt()/crypt_r() live in musl's libc -- so an ordinary -lcrypt links
	# the empty archive and resolves crypt() out of libc. That is the whole
	# mechanism, and it is why deleting the generic name is correct rather
	# than merely tidy: the empty archive already answers it.
	#
	# r4 and r5 each got this wrong in opposite directions -- r4 re-exposed
	# libxcrypt's real implementation as the generic name, r5 invented a
	# linker-script shim that was redundant with the empty archive. Neither
	# was needed.
	#
	# What this package DOES owe the tree is a link name of its own, so that
	# a consumer can opt into the extended hashes deliberately instead of
	# by accident. The SONAME stays libcrypt.so.2 (XCRYPT_2.0 floor, so
	# already-linked binaries keep running), and libxcrypt.so is the same
	# object under a name nothing else can collide with. There is no
	# libxcrypt.a because the build is --disable-static; the empty generic
	# libcrypt.a is musl's and is unaffected either way.
	ln -s /lib/libcrypt.so.2 "$PKGDEST/usr/lib/libxcrypt.so"
	ln -s /lib/libcrypt.so.2 "$PKGDEST/usr/lib/libxcrypt/libcrypt.so"
	# The explicit interface is pkg-config libxcrypt; the global
	# libcrypt.pc masquerades as the default provider (nothing in
	# /recipes consumes it - verified 2026-09-16) and goes.
	sed -i \
		-e 's|^Cflags:.*|Cflags: -I${includedir}/libxcrypt|' \
		-e 's|^Libs:.*|Libs: -lxcrypt|' \
		"$PKGDEST/usr/lib/pkgconfig/libxcrypt.pc"
	rm -f "$PKGDEST/usr/lib/pkgconfig/libcrypt.pc"
	# Generic crypt manuals belong to man-pages (verified complete
	# overlap census 2026-09-16: only crypt.3 + crypt_r.3 collide;
	# the 8 extended pages are unique to libxcrypt-doc and stay).
	rm -f "$PKGDEST/usr/share/man/man3/crypt.3" \
		"$PKGDEST/usr/share/man/man3/crypt_r.3"
	# Ownership asserts: musl alone owns the global crypt NAMESPACE. The
	# header and the global pc file stay gone. The -lcrypt link name stays
	# too, but it must be the empty compatibility stub, never libxcrypt's
	# implementation: that is what keeps generic -lcrypt meaning musl.
	test ! -e "$PKGDEST/usr/include/crypt.h" || {
		echo "ERROR: global crypt.h still staged" >&2; return 1; }
	test ! -e "$PKGDEST/usr/lib/pkgconfig/libcrypt.pc" || {
		echo "ERROR: global libcrypt.pc still staged" >&2; return 1; }
	test ! -e "$PKGDEST/usr/lib/libcrypt.so" || {
		echo "ERROR: global libcrypt.so staged; the generic -lcrypt name" >&2
		echo "       belongs to musl, whose empty libcrypt.a answers it." >&2
		return 1
	}
	test ! -e "$PKGDEST/usr/lib/libcrypt.a" || {
		echo "ERROR: a real generic libcrypt.a is staged; the empty" >&2
		echo "       compatibility archive belongs to musl-dev." >&2
		return 1
	}
	# The opt-in name must exist, or nobody can select the extended hashes.
	# -L, not -e: the link target is absolute (/lib/...), and -e would
	# resolve it against the build root instead of the staging tree.
	[ -L "$PKGDEST/usr/lib/libxcrypt.so" ] || {
		echo "ERROR: libxcrypt.so missing; a consumer cannot opt into the" >&2
		echo "       extended hashes deliberately." >&2
		return 1
	}
	# FHS placement: the runtime SONAME chain serves /bin + /sbin
	# consumers, so it lives in /lib; /usr/lib keeps only the
	# opt-in/dev names pointing back.
	test -f "$PKGDEST/lib/libcrypt.so.2.0.0" || {
		echo "ERROR: runtime libcrypt.so.2.0.0 missing from /lib" >&2; return 1; }
	test -L "$PKGDEST/lib/libcrypt.so.2" || {
		echo "ERROR: SONAME link libcrypt.so.2 missing from /lib" >&2; return 1; }
	test ! -e "$PKGDEST/usr/lib/libcrypt.so.2.0.0" || {
		echo "ERROR: runtime libcrypt.so.2.0.0 staged in /usr/lib (belongs in /lib)" >&2; return 1; }
	# Stage1-leak guard (2026-10-19 file fossil incident): a clean
	# native build must never embed /saphirabuild stage paths.
	if grep -rqF '/saphirabuild/' "$PKGDEST"; then
		echo "ERROR: staged payload leaks /saphirabuild stage path" >&2
		return 1
	fi
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
	# The pc file must name the package's OWN link name. A private -L plus
	# the generic -lcrypt would be the same collision the r3 split exists to
	# prevent, and would silently pull the extended implementation into any
	# consumer that merely ran pkg-config.
	grep -q -- "-lxcrypt" \
		"$PKGDEST/usr/lib/pkgconfig/libxcrypt.pc" || {
		echo "ERROR: libxcrypt.pc does not name -lxcrypt" >&2; return 1; }
	if grep -q -- "-lcrypt" \
		"$PKGDEST/usr/lib/pkgconfig/libxcrypt.pc"; then
		echo "ERROR: libxcrypt.pc still names the generic -lcrypt" >&2
		echo "       it must name -lxcrypt so the opt-in is explicit." >&2
		return 1
	fi
	grep -q crypt_gensalt "$PKGDEST/usr/include/libxcrypt/crypt.h" || {
		echo "ERROR: private crypt.h lacks extended API" >&2; return 1; }
}

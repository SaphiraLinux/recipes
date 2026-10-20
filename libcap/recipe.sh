#!/bin/sh

pkgname=libcap
pkgver=2.78
# r2: FHS non-usrmerged — /sbin/start-stop-daemon +
# supervise-daemon link libcap, so the runtime SONAME chain ships
# in /lib (verified 2026-10-19 via ldd). Dev linker name stays in
# /usr/lib pointing back (acl/zstd precedent). Egg carries unowned
# stage1 fossils in /lib; the package must stage the runtime in /lib.
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="POSIX.1e capabilities suite"
license="GPL-2.0-only"
origin=libcap
repo=main
url=https://sites.google.com/site/fullycapable/
source=https://www.kernel.org/pub/linux/libs/security/linux-privs/libcap2/libcap-${pkgver}.tar.xz
sha256=0d621e562fd932ccf67b9660fb018e468a683d7b827541df27813228c996bb11

depends=""

makedepends="
    binutils
    gcc
    saphira-linux-uapi-headers
    make
    perl
    pkgconf
"

subpackages="
    $pkgname-dev
    $pkgname-doc
"

recipe_build()
{
	make -C "$SRC" GOLANG=no
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" prefix=/usr lib=lib \
		PKGCONFIGDIR=/usr/lib/pkgconfig \
		SBINDIR=/usr/bin LIBDIR=/usr/lib exec_prefix=/usr \
		GOLANG=no RAISE_SETFCAP=no install
	# FHS non-usrmerged: /sbin consumers (start-stop-daemon,
	# supervise-daemon) need the runtime SONAME chain in /lib.
	# The /usr/lib/libcap.so linker name is a development artefact,
	# not usrmerge: it points at the absolute /lib target. No
	# relative ../ cross-tree links.
	mkdir -p "$PKGDEST/lib"
	for lib in "$PKGDEST/usr/lib/libcap.so.2"*; do
		[ -e "$lib" ] && mv "$lib" "$PKGDEST/lib/"
	done
	ln -sf /lib/libcap.so.2 "$PKGDEST/usr/lib/libcap.so"
	# Stage1-leak guard (2026-10-19 file fossil incident): a clean
	# native build must never embed /saphirabuild stage paths.
	if grep -rqF '/saphirabuild/' "$PKGDEST"; then
		echo "ERROR: staged payload leaks /saphirabuild stage path" >&2
		return 1
	fi
}

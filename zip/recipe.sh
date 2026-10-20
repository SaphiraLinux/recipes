#!/bin/sh

pkgname=zip
pkgver=3.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Create ZIP archives (Info-ZIP; rabbitmq escript packaging needs the zip creator)"
license='Info-ZIP'
origin=zip
repo=main
url=https://infozip.sourceforge.net/Zip.html
source=https://downloads.sourceforge.net/infozip/zip30.tar.gz
sha256=f0e8bb1f9b7eb0b01285495a2699df3a4b766784c1765a8f1aeedf63c0806369

depends="
    bzip2
"

makedepends="
    binutils
    bzip2-dev
    gcc
    make
"

subpackages=""

# Same family idiom as the native unzip recipe (same upstream,
# same URL style, same license). The generic target probes the
# toolchain via unix/configure (local only, no network) and builds
# the full suite: zip, zipcloak, zipnote, zipsplit.
# 1990s probe discipline: unix/configure tests memset/opendir/errno
# with test programs that omit the headers, which GCC 14+ rejects
# by default (-Werror=implicit-function-declaration,
# -Werror=implicit-int), so the probes misdetect present libc
# features as missing (notably -DZMEM, whose char*-based
# declarations then collide with string.h). Restoring the warning
# behavior through CC lets the probes evaluate what they probe:
# linkability, not header discipline. The real sources include
# their headers and compile warning-clean.
recipe_build()
{
	make -C "$SRC" -f unix/Makefile generic \
		CC="gcc -Wno-error=implicit-function-declaration -Wno-error=implicit-int"
}

recipe_install()
{
	for b in zip zipcloak zipnote zipsplit; do
		install -D -m 0755 "$SRC/$b" "$PKGDEST/usr/bin/$b"
		install -D -m 0644 "$SRC/man/$b.1" \
			"$PKGDEST/usr/share/man/man1/$b.1"
	done
}

#!/bin/sh
pkgname=tzdata
pkgver=2026a
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='IANA time zone database (zoneinfo)'
license='Public-Domain'
origin=tzdata
repo=saphira
url=https://www.iana.org/time-zones
# Vendored: https://data.iana.org/time-zones/releases/tzdata2026a.tar.gz
tzdata_sha256=77b541725937bb53bd92bd484c0b43bec8545e2d3431ee01f04ef8f2203ba2b7
depends=""
makedepends="gawk gcc make"
# zic (the compiler) comes from the tzcode release; zoneinfo data from
# the tzdata release. Both vendored, both hash-pinned.
tzcode_sha256=f80a17a2eddd2b54041f9c98d75b0aa8038b016d7c5de72892a146d9938740e1

recipe_build() {
	mkdir -p "$SRC/tzcode" "$SRC/tzdata"
	tar --no-same-owner -C "$SRC/tzcode" -xf "$RECIPE_DIR/files/tzcode2026a.tar.gz"
	tar --no-same-owner -C "$SRC/tzdata" -xf "$RECIPE_DIR/files/tzdata2026a.tar.gz"
	echo "$tzcode_sha256  $RECIPE_DIR/files/tzcode2026a.tar.gz" | sha256sum -c -
	echo "$tzdata_sha256  $RECIPE_DIR/files/tzdata2026a.tar.gz" | sha256sum -c -
	: > "$SRC/tzcode/version.h"
	printf '#ifndef TZDIR\n# define TZDIR "/usr/share/zoneinfo"\n#endif\n' \
		> "$SRC/tzcode/tzdir.h"
	gcc -O2 -DTZDEFAULT='"/etc/localtime"' \
		-DTZDEFRULES='"/usr/share/zoneinfo/Etc/UTC"' \
		-DVERSION='"2026a"' -DTZVERSION='"2026a"' \
		-DPKGVERSION='"(saphira-tzdata) "' -DREPORT_BUGS_TO='""' \
		-o "$SRC/tzcode/zic" "$SRC/tzcode/zic.c"
	mkdir -p "$PKGDEST/usr/share/zoneinfo" "$PKGDEST/etc"
	cd "$SRC/tzdata"
	Z="$SRC/tzcode/zic"
	D="$PKGDEST/usr/share/zoneinfo"
	"$Z" -d "$D" africa antarctica asia australasia europe \
		northamerica southamerica etcetera backward factory
	"$Z" -d "$D" -p America/New_York
	"$Z" -d "$D" -l Etc/UTC -t "$PKGDEST/etc/localtime"
	cp -f iso3166.tab zone.tab zone1970.tab "$D/"
}
recipe_install() {
	:
}

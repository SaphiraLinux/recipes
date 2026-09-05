#!/bin/sh

pkgname=sysstat
pkgver=12.7.9
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='System performance monitoring tools (sar, sadc, iostat, mpstat)'
license='GPL-2.0-or-later'
origin=sysstat
repo=saphira
url=https://github.com/sysstat/sysstat
# Vendored: https://github.com/sysstat/sysstat/archive/refs/tags/v12.7.9.tar.gz
sysstat_sha256=e48fc69401135dc08d2cd4ff58dbdbfce9b7485f76fc9049d97848e313c08dda

# r1: Saphira layout fix. Upstream configure picks $AuxPrefix/lib64 for
# sadc whenever a 64-bit host is detected - forbidden on Saphira. sa
# directories forced to /usr/lib/sa via the sa_lib_dir configure var.
depends=""
makedepends="
	binutils
	gawk
	gcc
	gettext
	saphira-kernel-headers=7.1.5
	make
"

recipe_build()
{
	SYBALL="$RECIPE_DIR/files/sysstat-12.7.9.tar.gz"
	echo "$sysstat_sha256  $SYBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$SYBALL"
	cd "$SRC"
	./configure --prefix=/usr \
		--disable-man-group \
		sa_lib_dir=/usr/lib/sa \
		sa_dir=/var/log/sa
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install MANGRPARG= CHOWNARG=
}

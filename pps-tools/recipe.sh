#!/bin/sh

pkgname=pps-tools
pkgver=1.0.3
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='LinuxPPS user-space tools and RFC2783 header (ppstest/ppswatch/ppsctl/ppsldisc, sys/timepps.h)'
license='GPL-2.0-or-later'
origin=pps-tools
repo=saphira
url=https://github.com/redlab-i/pps-tools
source=https://github.com/redlab-i/pps-tools/archive/v1.0.3.tar.gz
sha256=89163e29f1a4a0a702bbe25b900fd37d2eb86442329cefee58847e57e1964d7a

# The tools link only -lm (musl libc, implicit): no runtime deps.
depends=""

# timepps.h includes <linux/pps.h> (kernel UAPI) alongside musl's
# <sys/time.h>/<sys/ioctl.h>; the UAPI headers must be explicit.
makedepends="binutils gcc make saphira-linux-uapi-headers"
subpackages="$pkgname-dev"

recipe_build() {
	# Basename follows the URL (upstream tags releases vX.Y.Z).
	PPS_BALL="$RECIPE_DIR/files/v${pkgver}.tar.gz"
	echo "$sha256  $PPS_BALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$PPS_BALL"
	make -C "$SRC" -j${JOBS:-$(nproc)}
}

recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
	# Upstream installs exactly: usr/bin/ppsfind,ppstest,ppsctl,
	# ppswatch,ppsldisc and usr/include/sys/timepps.h (the RFC2783
	# API gpsd's SConscript probes for KPPS). The header travels to
	# -dev via the automatic usr/include split; the tools stay main.
	# ppsldisc attaches the PPS line discipline (ldattach equivalent)
	# for serial-PPS GPS receivers alongside kernel PPS_CLIENT_LDISC.
	for p in usr/bin/ppstest usr/bin/ppswatch usr/bin/ppsctl \
		usr/bin/ppsldisc usr/bin/ppsfind \
		usr/include/sys/timepps.h; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: pps-tools payload is missing $p" >&2
			return 1
		}
	done
}

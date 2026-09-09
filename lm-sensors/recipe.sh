#!/bin/sh

# Hardware health sensors (libsensors + sensors tooling). sensord is
# gone upstream since 3.6, so there is no daemon/RRD footprint: user
# space only.

pkgname=lm-sensors
pkgver=3.6.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Hardware health sensors"
license="GPL-2.0-or-later"
origin=lm-sensors
repo=saphira
url=https://hwmon.wiki.kernel.org/lm_sensors
source=https://github.com/lm-sensors/lm-sensors/archive/refs/tags/V3-6-2.tar.gz
sha256=c6a0587e565778a40d88891928bf8943f27d353f382d5b745a997d635978a8f0

depends=""

makedepends="
    binutils
    bison
    flex
    gcc
    make
"

recipe_build()
{
	make -j${JOBS:-$(nproc)} user CC=gcc
}

recipe_install()
{
	make PREFIX=/usr DESTDIR="$PKGDEST" user_install
}

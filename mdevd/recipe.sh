#!/bin/sh

pkgname=mdevd
pkgver=0.1.8.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Skarnet kernel event manager daemon (mdev-compatible, no fork)"
license='ISC'
origin=mdevd
repo=saphira
url=https://skarnet.org/software/mdevd/
# Upstream advertises 0.1.8.3 on the project page but does not serve
# its tarball (404 at publication time; the newest git tag is also
# 0.1.8.2). This packages 0.1.8.2 from the GitHub mirror with a
# locally computed hash; bump to 0.1.8.3 with the upstream-published
# hash once skarnet.org serves it.
source=https://github.com/skarnet/mdevd/archive/refs/tags/v0.1.8.2.tar.gz
sha256=23e242d70492b5381cab2227dd5b5407f748e52fe7a5df919a352c8dae26919d

depends="skalibs"

makedepends="
    binutils
    gcc
    make
    skalibs
    skalibs-dev
"

# Packaged, not built: the s6 suite is staged while the rust
# toolchain rebuild occupies the daemon. mdevd is order-independent
# past skalibs. No service is enabled here: mdevd as the device
# manager is an image-level decision (it replaces udev), and Egg
# stays on its current stack regardless.
disabled=yes
disabled_reason='staged with the s6 suite while the rust rebuild holds the daemon; enable any time after skalibs'

recipe_build()
{
	cd "$SRC" && ./configure \
		--prefix=/usr \
		--libdir=/usr/lib \
		--dynlibdir=/usr/lib \
		--includedir=/usr/include \
		--sysdepdir=/usr/lib/skalibs/sysdeps
	make
}

recipe_install()
{
	DESTDIR="$PKGDEST" make -C "$SRC" install
	install -D -m 0644 "$SRC/COPYING" \
		"$PKGDEST/usr/share/licenses/mdevd/COPYING"
	for p in \
		usr/bin/mdevd \
		usr/bin/mdevd-coldplug \
	; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: mdevd payload is missing $p" >&2
			return 1
		}
	done
}

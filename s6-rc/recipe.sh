#!/bin/sh

pkgname=s6-rc
pkgver=0.7.0.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Skarnet service manager for s6 systems (dependency-based boot)"
license='ISC'
origin=s6-rc
repo=saphira
url=https://skarnet.org/software/s6-rc/
source=https://skarnet.org/software/s6-rc/s6-rc-0.7.0.0.tar.gz
sha256=bf5b8ce0da5a4ee70d642b818b61d9916a7a9b64a457595f388113e54a188688

depends="skalibs execline s6"

makedepends="
    binutils
    gcc
    make
    skalibs
    skalibs-dev
    execline
    execline-dev
    s6
    s6-dev
"

subpackages="s6-rc-dev"

# Packaged, not built: the s6 suite is staged while the rust
# toolchain rebuild occupies the daemon. Enable in dependency
# order once the queue clears (after s6, before s6-linux-init).
# Service databases live in images, not in this package; no
# units ship and nothing auto-enables.
disabled=yes
disabled_reason='staged for the s6 init option while the rust rebuild holds the daemon; enable after s6, before s6-linux-init'

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
		"$PKGDEST/usr/share/licenses/s6-rc/COPYING"
	for p in \
		usr/bin/s6-rc \
		usr/bin/s6-rc-init \
		usr/bin/s6-rc-compile \
	; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: s6-rc payload is missing $p" >&2
			return 1
		}
	done
}

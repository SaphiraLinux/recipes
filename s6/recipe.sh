#!/bin/sh

pkgname=s6
pkgver=2.15.1.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Skarnet supervision suite (s6-svscan, s6-ipcserver superserver, process tools)"
license='ISC'
origin=s6
repo=saphira
url=https://skarnet.org/software/s6/
source=https://skarnet.org/software/s6/s6-2.15.1.0.tar.gz
sha256=eab9c46e22b66b16135f9a05ec68a0ea287d9060b84d10defaaa2caad158ab52

depends="skalibs execline"

makedepends="
    binutils
    gcc
    make
    skalibs
    skalibs-dev
    execline
    execline-dev
"

subpackages="s6-dev"

# Packaged, not built: the s6 suite is staged while the rust
# toolchain rebuild occupies the daemon. Enable in dependency
# order once the queue clears: skalibs, execline, then this
# package, then s6-rc, s6-linux-init (mdevd and nsss any time
# after skalibs). No service units ship here: s6 supervision
# trees and the s6-linux-init stage 1 are image-assembly work,
# not package payload, and Egg stays on OpenRC regardless.
disabled=yes
disabled_reason='staged for the s6 init option while the rust rebuild holds the daemon; enable after execline, before s6-rc'

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
		"$PKGDEST/usr/share/licenses/s6/COPYING"
	for p in \
		usr/bin/s6-svscan \
		usr/bin/s6-ipcserver \
		usr/bin/s6-supervise \
	; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: s6 payload is missing $p" >&2
			return 1
		}
	done
}

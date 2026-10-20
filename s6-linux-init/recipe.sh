#!/bin/sh

pkgname=s6-linux-init
pkgver=1.2.0.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Skarnet stage-1 init maker for s6-based systems"
license='ISC'
origin=s6-linux-init
repo=saphira
url=https://skarnet.org/software/s6-linux-init/
source=https://skarnet.org/software/s6-linux-init/s6-linux-init-1.2.0.2.tar.gz
sha256=6fad014da162c0c81924197c57d16e1a75c133b34a20e423431a1b741e907b1d

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

subpackages="s6-linux-init-dev"

# Packaged, not built: the s6 suite is staged while the rust
# toolchain rebuild occupies the daemon. Enable in dependency
# order once the queue clears (after s6-rc; mdevd and nsss are
# order-independent past skalibs). The generated stage-1 init,
# Getty respawn and the s6-rc service database are image-assembly
# work that comes after the packages build; nothing here boots
# anything and Egg stays on OpenRC regardless.
disabled=yes
disabled_reason='staged for the s6 init option while the rust rebuild holds the daemon; enable after s6-rc'

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
		"$PKGDEST/usr/share/licenses/s6-linux-init/COPYING"
	for p in \
		usr/bin/s6-linux-init-maker \
		usr/bin/s6-linux-init-shutdown \
	; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: s6-linux-init payload is missing $p" >&2
			return 1
		}
	done
}

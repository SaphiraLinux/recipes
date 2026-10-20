#!/bin/sh

pkgname=execline
pkgver=2.9.9.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Skarnet small scripting language (s6/s6-rc scripting foundation)"
license='ISC'
origin=execline
repo=saphira
url=https://skarnet.org/software/execline/
source=https://skarnet.org/software/execline/execline-2.9.9.2.tar.gz
sha256=908ed4db3a6b3a23a205d8fd4cf2a71089156f2aeae0f54656045aafad2dee32

depends="skalibs"

makedepends="
    binutils
    gcc
    make
    skalibs
    skalibs-dev
"

subpackages="execline-dev"

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
		"$PKGDEST/usr/share/licenses/execline/COPYING"
	for p in \
		usr/bin/execline \
	; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: execline payload is missing $p" >&2
			return 1
		}
	done
}

# Packaged, not built: the s6 suite is staged while the rust
# toolchain rebuild occupies the daemon. Enable in dependency
# order once the queue clears: skalibs, then this package, then
# s6, s6-rc, s6-linux-init (mdevd and nsss any time after
# skalibs). Single multicall binary plus symlinks, per upstream.
disabled=yes
disabled_reason='staged for the s6 init option while the rust rebuild holds the daemon; enable after skalibs, before s6'

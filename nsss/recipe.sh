#!/bin/sh

pkgname=nsss
pkgver=0.2.1.3
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Skarnet small statically-linkable NSS alternative (switch daemon + libs)"
license='ISC'
origin=nsss
repo=saphira
url=https://skarnet.org/software/nsss/
source=https://skarnet.org/software/nsss/nsss-0.2.1.3.tar.gz
sha256=14da444a836d24b6a286fac88a502bdaa296a4d328f09d5297568ad3b3e02685

depends="skalibs"

makedepends="
    binutils
    gcc
    make
    skalibs
    skalibs-dev
"

subpackages="nsss-dev"

# Packaged, not built: staged with the s6 suite while the rust
# toolchain rebuild occupies the daemon. Order-independent past
# skalibs. Deliberate packaging decision: the top-level
# pwd.h/grp.h forwarding headers are NOT installed. They would
# shadow musl's headers for every subsequent build in the repo
# (same names, different providers); musl stays authoritative and
# the nsss/*.h API remains available explicitly under
# /usr/include/nsss. Revisit only as a reviewed NSS-integration
# decision, never as a side effect.
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
	rm -f "$PKGDEST/usr/include/pwd.h" "$PKGDEST/usr/include/grp.h"
	install -D -m 0644 "$SRC/COPYING" \
		"$PKGDEST/usr/share/licenses/nsss/COPYING"
	for p in \
		usr/bin/nsssd-unix \
		usr/bin/nsssd-switch \
		usr/include/nsss/nsss.h \
	; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: nsss payload is missing $p" >&2
			return 1
		}
	done
	[ -n "$(find "$PKGDEST/usr/lib" -maxdepth 1 -name 'libnsss.so*')" ] || {
		echo "ERROR: nsss payload has no libnsss" >&2
		return 1
	}
}

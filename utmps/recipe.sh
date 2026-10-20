#!/bin/sh

pkgname=utmps
pkgver=0.1.3.4
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Skarnet secure utmp/wtmp implementation (daemons, client library, tools)"
license='ISC'
origin=utmps
repo=saphira
url=https://skarnet.org/software/utmps/
source=https://skarnet.org/software/utmps/utmps-0.1.3.4.tar.gz
sha256=12dcc102ad6ac81f81aecc4950733db94f35081947054b9b1473cac5c90810bc

depends="skalibs"

makedepends="
    binutils
    gcc
    make
    skalibs
    skalibs-dev
"

subpackages="utmps-dev"

# Standard skarnet build. Sockets default to /run/utmps/*, matching
# the Saphira /run split; sysdeps resolve from the native skalibs
# install at the same prefix. No service units ship yet: the
# daemons (utmps-utmpd, utmps-wtmpd) are UCSPI programs that need a
# Unix-domain superserver (s6-ipcserver or equivalent), which no
# Saphira package provides today - shipping units that cannot run
# would be a broken promise. Daemon runtime (superserver choice,
# utmp identity, enablement) is a tracked follow-up; the library,
# headers and offline tools are usable now. See saphira-utmp, which
# writes the boot-time records directly until the daemons run.
recipe_build()
{
	cd "$SRC" && ./configure \
		--prefix=/usr
	make
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
	install -D -m 0644 "$SRC/COPYING" \
		"$PKGDEST/usr/share/licenses/utmps/COPYING"
	for p in \
		usr/bin/utmps-write \
		usr/bin/utmps-utmpd \
		usr/bin/utmps-wtmpd \
	; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: utmps payload is missing $p" >&2
			return 1
		}
	done
}

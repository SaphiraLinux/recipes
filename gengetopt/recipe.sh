#!/bin/sh

pkgname=gengetopt
pkgver=2.23
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='gengetopt command-line option parser generator (libidn2 bootstrap needs it)'
license='GPL-3.0-or-later'
origin=gengetopt
repo=main
url=https://www.gnu.org/software/gengetopt/
source=https://ftp.gnu.org/gnu/gengetopt/gengetopt-2.23.tar.xz
sha256=b941aec9011864978dd7fdeb052b1943535824169d2aa2b0e7eae9ab807584ac
# r1: initial native port. Build-time tool for gnulib-bootstrap
# consumers (libidn2 generates idn2_cmd.c/.h from idn2.ggo with it);
# no runtime consumers link it.

depends=""
# texinfo is a real published dep (7.2-r2): doc/ builds .info/.html
# with $(MAKEINFO) directly, not via missing(1), so stubbing MAKEINFO
# with true breaks the html rule (it mv's a file true never creates).
# Upstream's docs build unmodified instead.
makedepends="gcc binutils make saphira-kernel-headers texinfo"

recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/gengetopt-2.23.tar.xz" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/gengetopt-2.23.tar.xz"
	cd "$SRC"
	./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
}

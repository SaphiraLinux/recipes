#!/bin/sh

pkgname=tree
pkgver=2.3.2
# r3: fix install paths. Upstream's Makefile abuses DESTDIR to mean
# BINDIR (DESTDIR defaults to ${PREFIX}/bin) and does not prefix
# MANDIR, so DESTDIR=$PKGDEST staged the binary at the package
# root (/tree on target) and the man page leaked into the build
# root. Stage both under PKGDEST explicitly (LFS form).
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Recursive directory listing tool'
license='GPL-2.0-or-later'
origin=tree
repo=saphira
url=http://mama.indstate.edu/users/ice/tree/
source=https://github.com/Old-Man-Programmer/tree/archive/refs/tags/${pkgver}.tar.gz
sha256=22cf32e84e3eb508d97a9e991c2c3cc006b9dcf4afed201d96311c5c57d08fcf

makedepends="gcc make"

subpackages="$pkgname-doc"

recipe_build()
{
	cd "$SRC"
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC" PREFIX=/usr DESTDIR="$PKGDEST/usr/bin" \
		MANDIR="$PKGDEST/usr/share/man" install
	test -x "$PKGDEST/usr/bin/tree" ||
		{ echo "ERROR: tree binary not staged at usr/bin/tree" >&2; return 1; }
	test -f "$PKGDEST/usr/share/man/man1/tree.1" ||
		{ echo "ERROR: tree man page not staged" >&2; return 1; }
}

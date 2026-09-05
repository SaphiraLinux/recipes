#!/bin/sh

pkgname=fakeroot
pkgver=2.1.4
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Tool for simulating superuser privileges"
license="GPL-3.0-or-later"
origin=fakeroot
repo=main
url=https://salsa.debian.org/clint/fakeroot
source=https://salsa.debian.org/clint/fakeroot/-/archive/upstream/${pkgver}/fakeroot-upstream-${pkgver}.tar.gz
sha256=b71f645037e5a44a474efd641b353b506db3803eb60ed90a4ac6322a8d96d340

depends=""

makedepends="
    acl-dev
    autoconf
    automake
    binutils
    gcc
    libtool
    make
"

recipe_build()
{
	# Repository automake 1.18.1-r0 lacks the unversioned macro directory
	# that aclocal requires; create it here until repackaged automake lands.
	[ -d /usr/share/aclocal ] || install -d /usr/share/aclocal
	# Repository coreutils ships /bin/env while scripts such as libtoolize
	# carry an absolute #!/usr/bin/env shebang; link it here until the
	# coreutils packaging is repaired.
	[ -e /usr/bin/env ] || [ -L /usr/bin/env ] || ln -s /bin/env /usr/bin/env
	# The verified upstream tag archive contains configure.ac rather than a
	# generated configure script.  Generate it inside the Saphira build root.
	autoreconf -fi
	# musl has no _STAT_VER/__xstat internals, so the glibc-only symbol
	# shims in libfakeroot_time64_entry.c must stay inert; the musl paths
	# in libfakeroot.c handle interception themselves.
	CPPFLAGS="${CPPFLAGS-} -DNO_WRAP_STAT_SYMBOL -DNO_WRAP_LSTAT_SYMBOL \
-DNO_WRAP_FSTAT_SYMBOL -DNO_WRAP_FSTATAT_SYMBOL -DNO_WRAP_STAT64_SYMBOL \
-DNO_WRAP_LSTAT64_SYMBOL -DNO_WRAP_FSTAT64_SYMBOL -DNO_WRAP_FSTATAT64_SYMBOL" \
	./configure \
		--prefix=/usr \
		--libdir=/usr/lib \
		--disable-static \
		ac_cv_func_capset=0
	make
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}

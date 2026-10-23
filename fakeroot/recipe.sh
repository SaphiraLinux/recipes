#!/bin/sh

pkgname=fakeroot
pkgver=2.1.4
pkgrel=2
# r2: SEV1 host-mutation removal (2026-10-22): recipe_build created
# /usr/share/aclocal and symlinked /usr/bin/env on the machine running the
# build - outside every authorized staging dir, and normalizing a merged-usr
# compat link. Both are provided inside authorized build roots (the automake
# recipe now ships its macro dir; root-init owns the ephemeral /usr/bin/env
# shim); outside them the build fails instead of repairing the host.
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
	# No host mutation, ever (see r2 header): the macro dir and the env
	# shim must already exist in an authorized build root. Fail closed
	# outside one rather than writing to absolute host paths.
	[ -d /usr/share/aclocal ] || {
		echo "ERROR: /usr/share/aclocal missing (needs repackaged automake in the build root; refusing to create it on the host)" >&2
		return 1
	}
	[ -e /usr/bin/env ] || [ -L /usr/bin/env ] || {
		echo "ERROR: /usr/bin/env missing (authorized build roots provide the ephemeral shim; refusing to create it on the host)" >&2
		return 1
	}
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
		--sysconfdir=/etc \
		--localstatedir=/var \
		--libdir=/usr/lib \
		--disable-static \
		ac_cv_func_capset=0
	make
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}

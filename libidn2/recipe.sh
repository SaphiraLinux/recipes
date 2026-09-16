#!/bin/sh

pkgname=libidn2
pkgver=2.3.8
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="GNU Internationalized Domain Name library v2 (qmail smtputf8/IDN needs it)"
license="LGPL-3.0-or-later GPL-2.0-or-later"
origin=libidn2
repo=main
url=https://gitlab.com/libidn/libidn2
subpackages="
    $pkgname-dev
"
# Upstream publishes via GitLab, not ftp.gnu.org (no gnu/libidn2
# directory exists there); the Debian .orig tarball is the pristine
# upstream release artifact (postfix recipe precedent).
source=https://deb.debian.org/debian/pool/main/libi/libidn2/libidn2_2.3.8.orig.tar.gz
sha256=bbad1678d35d28e2c62e6a2577083829461402d9e47b908791c55314a5cb5e04
# gnulib import source for the bootstrap below, pinned exactly to
# bootstrap.conf GNULIB_REVISION (tree verified byte-identical to the
# commit via git-archive diff; sidecar pins the transfer). Deliberately
# NOT a second vendor=/sha256= pair: buildpkg-single reads single
# source_url/source_sha256 with last-assignment-wins, so a duplicate
# sha256= would re-pin the source archive to the gnulib digest and
# fail the build. Extra tarballs use <name>_url/<name>_sha256 vars
# with inline verification in recipe_build (nginx module precedent);
# the worker builds $SRC from source=, the recipe extracts this one
# by hand.
gnulib_url=https://github.com/coreutils/gnulib/archive/c89cd2fbd3b9f3d7c5a146247256599714c91ec7.tar.gz
gnulib_sha256=5e4a8e2fc54ca6f6aa9b025ac847ff967c4cd1b01bf4c8e29e10626247eddf58

depends="
    libunistring
"

makedepends="
    autoconf
    automake
    binutils
    gawk
    gcc
    gengetopt
    gettext
    git
    gperf
    libtool
    libunistring-dev
    make
    perl
    pkgconf
"

recipe_build()
{
	# The Debian .orig is a raw upstream export, not a make-dist
	# tarball: no generated configure, and SUBDIRS needs a gnulib
	# import (gl/ + unistring/ hold only diffs). Bootstrap from the
	# vendored tree pinned above (Debian's method, hermetic: local
	# --gnulib-srcdir, --skip-po, no network, no --pull off the pin;
	# idn2_cmd.c/.h regenerate from idn2.ggo via the gengetopt dep
	# at make time). .tarball-version seeds the version for the
	# imported git-version-gen (no git history in-tree).
	mkdir -p "$BUILDDIR/gnulib"
	echo "$gnulib_sha256  $RECIPE_DIR/files/c89cd2fbd3b9f3d7c5a146247256599714c91ec7.tar.gz" | sha256sum -c -
	tar --no-same-owner -xzf "$RECIPE_DIR/files/c89cd2fbd3b9f3d7c5a146247256599714c91ec7.tar.gz" \
		-C "$BUILDDIR/gnulib" --strip-components=1
	printf '%s\n' '2.3.8' > .tarball-version
	# --no-git is load-bearing, not cosmetic: bootstrap.conf pins
	# GNULIB_REVISION, so without it bootstrap tries to git-checkout
	# the pin inside the vendored (non-git) tree and dies 128 before
	# the import that installs build-aux/git-version-gen. The pin is
	# honoured by vending the exact tree, never by fetching.
	./bootstrap --gnulib-srcdir="$BUILDDIR/gnulib" --skip-po --no-git
	# No autoreconf here: bootstrap ends with its own (AUTOPOINT=true
	# LIBTOOLIZE=true) autoreconf, and re-running it would re-install
	# the stale gettext-era m4 shadows bootstrap deliberately removed
	# ("Removing older autopoint/libtool M4 macros"). The killer is
	# m4/wint_t.m4 serial 5 shadowing gl/m4/wint_t.m4 serial 11 via
	# AC_CONFIG_MACRO_DIRS order: gt_TYPE_WINT_T then lacks the
	# GNULIBHEADERS_OVERRIDE_WINT_T logic, the make variable stays
	# empty, and gl/stdint.h gets a bare "#if" (gcc hard error in
	# malloca.c). Fail fast if the shadows ever return.
	for shadow in codeset.m4 extern-inline.m4 fcntl-o.m4 iconv.m4 \
		lib-ld.m4 lib-link.m4 lib-prefix.m4 visibility.m4 wint_t.m4; do
		test ! -f "m4/$shadow" ||
			{ echo "ERROR: stale m4 shadow present: m4/$shadow" >&2; return 1; }
	done
	# Same GNU-family shape as libunistring: shared only. --disable-doc:
	# doc/idn2.1 regenerates via help2man (help2man chain not packaged -
	# coreutils "No man pages v1" precedent) and the export ships no
	# prebuilt page, so docs stay off until help2man lands. The idn
	# binary's --help remains the runtime reference.
	./configure 		--prefix=/usr 		--sysconfdir=/etc 		--localstatedir=/var 		--disable-static 		--disable-doc
	make
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}

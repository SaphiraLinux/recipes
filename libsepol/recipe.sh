#!/bin/sh

pkgname=libsepol
pkgver=3.11
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="SELinux binary policy manipulation library (LXC SELinux backend)"
license="LGPL-2.1-or-later"
origin=libsepol
repo=saphira
url=https://github.com/SELinuxProject/selinux
# Monorepo tarball, not the libsepol-only component archive: the
# tests/ suite includes ../checkpolicy/parse_util.h (sibling source
# tree), so the component tarball cannot build tests as upstream
# ships them (proven by the builder: CUnit resolved, parse_util.h
# missing). Only the libsepol subtree is built and installed.
source=https://github.com/SELinuxProject/selinux/releases/download/${pkgver}/selinux-${pkgver}.tar.gz
sha256=6b6d47ab0f35fe1c09bda0c62821c8d97a0cbe7f6e9404b338df7bde0182c4f4

# flex drives the CIL lexer (cil_lexer.l; the parser is hand-written, so
# libsepol itself needs no bison) and checkpolicy's policy_scan.l;
# bison drives checkpolicy's policy_parse.y. gcc/make are the explicit
# toolchain closure (musl headers come from the base root). cunit-dev
# is test-only: the tests/ suite includes <CUnit/Basic.h> (proven by
# the first builder run, which compiled the library clean and failed
# only on that header).
makedepends="
    binutils
    bison
    cunit-dev
    flex
    gcc
    make
"

subpackages="$pkgname-dev $pkgname-doc"

recipe_build()
{
	# Upstream honors PREFIX/DESTDIR/LIBDIR/INCLUDEDIR/SHLIBDIR.
	# Runtime objects stay in /usr/lib: every consumer (libselinux,
	# liblxc tools) lives under /usr, so /lib is not warranted.
	# Only the libsepol subtree is built (see source= comment).
	make -C libsepol -j${JOBS:-$(nproc)} \
		PREFIX=/usr \
		LIBDIR=/usr/lib \
		SHLIBDIR=/usr/lib \
		INCLUDEDIR=/usr/include
	# Upstream unit tests: pure userspace policy suites, no
	# namespaces or daemons required. They link six checkpolicy
	# parser objects and execute the checkpolicy binary itself,
	# so the sibling must be built first (never installed -- only
	# `make -C libsepol install` runs below). It links the
	# just-built in-tree static library via LDFLAGS.
	make -C checkpolicy -j${JOBS:-$(nproc)} \
		PREFIX=/usr \
		CPPFLAGS="-I$SRC/libsepol/include" \
		LDFLAGS="-L$SRC/libsepol/src"
	make -C libsepol \
		PREFIX=/usr \
		LIBDIR=/usr/lib \
		SHLIBDIR=/usr/lib \
		INCLUDEDIR=/usr/include \
		test
}

recipe_install()
{
	make -C libsepol DESTDIR="$PKGDEST" \
		PREFIX=/usr \
		LIBDIR=/usr/lib \
		SHLIBDIR=/usr/lib \
		INCLUDEDIR=/usr/include \
		install
	install -D -m 0644 "$SRC/libsepol/LICENSE" \
		"$PKGDEST/usr/share/licenses/libsepol/LICENSE"
	# The static archive and .pc file travel to -dev and the man
	# pages to -doc via the fixed buildpkg-single predicates; the
	# versioned .so and the sepol_* utils stay in main.
	for p in usr/lib/libsepol.so usr/include/sepol usr/share/man; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: libsepol payload is missing $p" >&2
			return 1
		}
	done
}

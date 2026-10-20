#!/bin/sh

pkgname=libapparmor
pkgver=4.1.8
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="AppArmor change-hat and confinement library (LXC AppArmor backend)"
license="LGPL-2.1-or-later"
origin=libapparmor
repo=saphira
url=https://apparmor.net/
# GitLab source archive, verified against the maintainer-published
# checksum in the v4.1.8 release notes
# (00f04344...). 4.1.x is the actively maintained stable line; 5.0.x
# exists but buys the first port nothing (the libapparmor C API LXC
# consumes is unchanged) while adding major-version churn risk.
source=https://gitlab.com/apparmor/apparmor/-/archive/v${pkgver}/apparmor-v${pkgver}.tar.gz
sha256=00f0434405f72b2a624587a92e56fd5e350af91077603b372706469f7c5e9757

# Only libraries/libapparmor is built (the parser, profiles and utils
# are separate upstream components, not needed for the LXC backend).
# bison+flex drive grammar.y/scanner.l; autoconf/automake/libtool
# regenerate configure from the git archive (no pregenerated
# configure ships); autoconf-archive provides the macros configure.ac
# requires (proven by the first builder run); perl provides pod2man
# for the man pages.
# Python/Perl/Ruby bindings default to off upstream -- nothing to
# disable (feature policy: no binding stack without a consumer).
makedepends="
    autoconf
    autoconf-archive
    automake
    binutils
    bison
    flex
    gcc
    libtool
    make
    perl
    pkgconf
"

subpackages="$pkgname-dev $pkgname-doc"

recipe_build()
{
	cd "$SRC/libraries/libapparmor"
	autoreconf -fi
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--libdir=/usr/lib
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC/libraries/libapparmor" DESTDIR="$PKGDEST" install
	install -D -m 0644 "$SRC/libraries/libapparmor/COPYING.LGPL" \
		"$PKGDEST/usr/share/licenses/libapparmor/COPYING.LGPL"
	# The .a archive and headers travel to -dev and the man pages
	# to -doc via the fixed buildpkg-single predicates; the
	# versioned .so stays in main (all consumers live under /usr).
	for p in usr/lib/libapparmor.so usr/include/sys/apparmor.h usr/share/man; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: libapparmor payload is missing $p" >&2
			return 1
		}
	done
}

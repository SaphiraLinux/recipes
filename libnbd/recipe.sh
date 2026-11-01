#!/bin/sh

# libnbd: Network Block Device client library (libvirt nbdkit
# storage backend probes libnbd, not nbdkit itself).

pkgname=libnbd
pkgver=1.24.4
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Network Block Device client library"
license="LGPL-2.1-or-later"
origin=libnbd
repo=saphira
url=https://libguestfs.org/
source=https://libguestfs.org/download/libnbd/1.24-stable/libnbd-${pkgver}.tar.gz
sha256=19dc521f2b8142ecd45d3009e191b60b76105b1c522b03ce0582adf74864b83b

# gnutls-dev: TLS support is core NBD functionality, not optional.
# fuse3-dev: nbdfuse FUSE client ships with the library.
# perl: pod2man generates the man pages (docs build fails without it).
# libxml2-dev: NBD URI support (libvirt addresses nbdkit by URI).
# glib only gates examples (not shipped); python bindings stay out
# (no consumer) — both match Alpine's shape minus py3, documented.
makedepends="
    binutils
    fuse3-dev
    gcc
    gnutls-dev
    libxml2-dev
    make
    perl
    pkgconf
"

subpackages="$pkgname-dev $pkgname-doc"

recipe_build()
{
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--libdir=/usr/lib
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	install -D -m 0644 "$SRC/COPYING.LIB" \
		"$PKGDEST/usr/share/licenses/libnbd/COPYING.LIB"
	# Upstream installs only libnbd.h; nbd-protocol.h (stable
	# on-wire protocol definitions, public interface) ships
	# explicitly from the source tree.
	install -D -m 0644 "$SRC/lib/nbd-protocol.h" \
		"$PKGDEST/usr/include/nbd-protocol.h"
	# .a/.pc/headers to -dev, man pages to -doc via the fixed split
	# predicates; the versioned .so and tools stay in main.
	for p in usr/lib/libnbd.so usr/include/nbd-protocol.h; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: libnbd payload is missing $p" >&2
			return 1
		}
	done
}

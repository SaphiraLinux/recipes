#!/bin/sh

# xen-libs: Xen control/library stack subset (libvirt libxl driver).
# Libraries only: no hypervisor, no daemons (xenstored/xenconsoled),
# no tools, no docs, no stub domains. The libxl driver needs
# libxenlight plus libxenctrl/libxenstore support libs, all built
# under tools/libs (+ public headers under tools/include).

pkgname=xen-libs
pkgver=4.20.4
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Xen control libraries (libxenlight and support libs)"
license="GPL-2.0-only AND LGPL-2.1-only"
origin=xen-libs
repo=saphira
url=https://xenproject.org/
source=https://downloads.xenproject.org/release/xen/${pkgver}/xen-${pkgver}.tar.gz
sha256=e8dc54812e9a06e1d960d234d3b8d9562f0ec54204cce696eb37488eb87eff52

# flex+bison build the util parsers; python3 drives the libxl IDL
# generators; yajl + uuid + libxml2 feed libxenlight linkage
# (RUNTIME eval proves the closure; openssl for completeness with
# the crypto-using helpers).
makedepends="
    binutils
    bison
    flex
    gcc
    libxml2-dev
    make
    openssl-dev
    perl
    pkgconf
    python3
    util-linux-dev
    yajl-dev
"

subpackages="$pkgname-dev $pkgname-doc"

recipe_build()
{
	cd "$SRC/tools"
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--libdir=/usr/lib \
		--disable-werror \
		--disable-monitors \
		--disable-ocamltools \
		--disable-xsmpolicy \
		--disable-seabios \
		--disable-golang \
		--disable-pygrub \
		--disable-pvshim
	make -C include -j${JOBS:-$(nproc)}
	make -C libs -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC/tools/include" DESTDIR="$PKGDEST" install
	make -C "$SRC/tools/libs" DESTDIR="$PKGDEST" install
	install -D -m 0644 "$SRC/COPYING" \
		"$PKGDEST/usr/share/licenses/xen-libs/COPYING"
	# .a/.pc/headers to -dev via the fixed split predicates; the
	# versioned runtime libs stay in main. libxenlight presence is
	# the load-bearing assert (libvirt probes xenlight>=4.9).
	for p in usr/lib/libxenlight.so usr/include/xen; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: xen-libs payload is missing $p" >&2
			return 1
		}
	done
}

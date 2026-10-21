#!/bin/sh

# open-isns: iSNS discovery service (open-iscsi links -lisns
# unconditionally). isnsd ships dual-init units, never enabled.

pkgname=open-isns
pkgver=0.103
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="iSNS discovery service and client library"
license="LGPL-2.1-or-later"
origin=open-isns
repo=saphira
url=https://github.com/open-iscsi/open-isns
source=https://github.com/open-iscsi/open-isns/archive/refs/tags/v${pkgver}.tar.gz
sha256=47499f3ce87a832840884dcf3eedbec8c039f472fe921a5378e3b206a3fc1a32

# -Dslp=disabled: Service Location Protocol needs openslp
# (absent; discovery works without it). security stays auto
# (musl crypt probing decides; evidence in the build log).
# -Dlibdir=/usr/lib: upstream hardcodes libdir=/usr/lib64 in
# default_options (meson.build:11); Saphira forbids lib64, and the
# CLI flag overrides the default (proven: without it the payload
# lands in usr/lib64 and the usr/lib assert fails).
makedepends="
    binutils
    gcc
    make
    meson
    ninja
    pkgconf
    python3
"

subpackages="$pkgname-dev $pkgname-doc"

recipe_build()
{
	meson setup build "$SRC" --prefix=/usr \
		--sysconfdir=/etc --localstatedir=/var \
		-Dlibdir=/usr/lib \
		-Dslp=disabled
	ninja -C build
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C build install
	rm -f "$PKGDEST/usr/lib/systemd/system/isnsd.service"
	install -D -m 0644 "$SRC/COPYING" \
		"$PKGDEST/usr/share/licenses/open-isns/COPYING"
	install -D -m 0755 "$RECIPE_DIR/files/isnsd.initd" \
		"$PKGDEST/etc/init.d/isnsd"
	install -D -m 0644 "$RECIPE_DIR/files/isnsd.service" \
		"$PKGDEST/usr/lib/systemd/system/isnsd.service"
	# .a/.pc/headers to -dev via the fixed split predicates; the
	# shared lib and isnsd stay in main. Headers live under
	# include/libisns (meson installs them there and consumers
	# include <libisns/...> — verified against open-iscsi 2.1.13);
	# there is no include/isns directory upstream.
	for p in usr/lib/libisns.so usr/include/libisns \
		usr/sbin/isnsd \
		etc/init.d/isnsd \
		usr/lib/systemd/system/isnsd.service; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: open-isns payload is missing $p" >&2
			return 1
		}
	done
}

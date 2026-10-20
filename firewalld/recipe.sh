#!/bin/sh

# firewalld: firewall daemon with D-Bus interface (libvirt
# firewalld zone support talks to it; nftables backend is primary).
# Ships dual-init units, never enabled at install.

pkgname=firewalld
pkgver=2.5.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Firewall daemon with D-Bus interface (nftables backend)"
license="GPL-2.0-or-later"
origin=firewalld
repo=saphira
url=https://firewalld.org/
source=https://github.com/firewalld/firewalld/releases/download/v${pkgver}/firewalld-${pkgver}.tar.bz2
sha256=99d7468c22f6cafd8c72aa53173a632f2ca29cb19aec913e8ed45b6102af322d

# Runtime closure proven from imports: dbus + dbus.mainloop (python-dbus)
# and GLib mainloop (pygobject) in both client and server; the system
# bus itself (dbus); nftables CLI for the documented backend. ebtables
# and ipset backends stay available if those tools are installed but
# are not dependencies.
depends="
    dbus
    nftables
    pygobject
    python-dbus
    python3
"

makedepends="
    binutils
    gcc
    glib-dev
    make
    pkgconf
    python3
    setuptools
"
# setuptools supplies the setuptools python module meson probes for
# (meson.build:29 fails closed without it). setuptools-80.10.2 is
# published; no new port needed for the build. Runtime pygobject +
# python-dbus (declared above) are separate follow-up ports required
# before any activation.

subpackages="$pkgname-doc"

recipe_build()
{
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--libdir=/usr/lib \
		--disable-docs \
		--disable-systemd \
		--with-systemd-unitdir=/usr/lib/systemd/system
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	install -D -m 0644 "$SRC/COPYING" \
		"$PKGDEST/usr/share/licenses/firewalld/COPYING"
	install -D -m 0755 "$RECIPE_DIR/files/firewalld.initd" \
		"$PKGDEST/etc/init.d/firewalld"
	# Upstream's own unit lands first; ours is authoritative
	# (packaged paths, never enabled).
	rm -f "$PKGDEST/usr/lib/systemd/system/firewalld.service"
	install -D -m 0644 "$RECIPE_DIR/files/firewalld.service" \
		"$PKGDEST/usr/lib/systemd/system/firewalld.service"
	for p in usr/sbin/firewalld \
		etc/init.d/firewalld \
		usr/lib/systemd/system/firewalld.service; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: firewalld payload is missing $p" >&2
			return 1
		}
	done
}

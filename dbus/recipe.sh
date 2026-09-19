#!/bin/sh
pkgname=dbus
pkgver=1.16.0
pkgrel=7
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='D-Bus message bus system'
license='GPL-2.0-or-later AFL-2.1'
origin=dbus
repo=saphira
url=https://www.freedesktop.org/wiki/Software/dbus/
dbus_sha256=9f8ca5eb51cbe09951aec8624b86c292990ae2428b41b856e2bed17ec65c8849
# Init-coupling invariant: dbus links libsystemd (socket activation)
# but must never resolve the PID-1 systemd package - that edge once
# dragged systemd onto OpenRC hosts. Runtime and build links go to
# the systemd-libs/systemd-dev splits only. A packaged .service unit
# never justifies a dependency on an init system.
depends="expat systemd-libs"
makedepends="meson ninja expat-dev gcc pkgconf saphira-kernel-headers systemd-dev"
subpackages="$pkgname-dev $pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/dbus-1.16.0.tar.xz"
	cd "$SRC"
	echo "$dbus_sha256  $RECIPE_DIR/files/dbus-1.16.0.tar.xz" | sha256sum -c -
	meson setup _build --prefix=/usr \
		-Dsystemd=enabled -Dsystemd_system_unitdir=/usr/lib/systemd/system \
		-Dx11_autolaunch=disabled -Dxml_docs=disabled \
		-Dmodular_tests=disabled \
		-Dsysconfdir=/etc -Dlocalstatedir=/var \
		-Druntime_dir=/var/run
	# r7: runtime_dir /run -> /var/run (split-/run invariant): the
	# system bus socket becomes /var/run/dbus/system_bus_socket
	# (meson derives it as prefix/runstatedir/dbus/system_bus_socket;
	# the shipped dbus.socket unit carries it, systemd creates the
	# parents for socket units). Payload change, revision bumps.
	meson compile -C _build
}
recipe_install() {
	DESTDIR="$PKGDEST" meson install -C "$SRC/_build"
	# Dual-init policy: the systemd bus unit ships via meson; the OpenRC
	# counterpart ships from files/ - neither wraps the other, neither
	# is auto-enabled.
	install -D -m 0755 "$RECIPE_DIR/files/dbus.initd" \
		"$PKGDEST/etc/init.d/dbus"
	# FHS migration declaration (hotfix/var-packaging-bug-var-run-isnot-run):
	# messagebus owns the corrected runtime dir; makepkg runs
	# ensure-fhs after ensure-identity on install/upgrade.
	install -D -m 0644 "$RECIPE_DIR/files/fhs.d/dbus" \
		"$PKGDEST/usr/share/saphira/fhs.d/dbus"
	# Runtime identity declaration: messagebus:81 required by the
	# system bus. makepkg generates the install scripts from this
	# fragment; the package creates its identity at install time.
	# r4: fragment added (payload change, revision bumps).
	# r6: dbus.legacy sidecar (hatchling pre-canonical messagebus
	# 65535:100/983): exact matches auto-migrate during install,
	# upgrade and repair, so apk fix dbus self-heals (no manual
	# saphira-identity reconcile step).
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/dbus" \
		"$PKGDEST/usr/share/saphira/accounts.d/dbus"
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/dbus.legacy" \
		"$PKGDEST/usr/share/saphira/accounts.d/dbus.legacy"
}

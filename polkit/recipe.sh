#!/bin/sh
pkgname=polkit
pkgver=127
pkgrel=2
# r2: polkitd UID/GID 127 -> 156. UID 127 belongs to systemd-network
# (senior holding since 261.2-r5; the hatched tombstone reserves it
# eternally and IDs never recycle to unrelated identities), so the r1
# claim could never register in hatched. 156 verified free in tree
# fragments and both generations' ledgers. polkitd deployed nowhere
# yet (no passwd entry on Egg/minimer), so the move is consequence-free.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Privilege authorization framework (polkitd, fwupd dependency)'
license='LGPL-2.0-or-later'
origin=polkit
repo=saphira
url=https://github.com/polkit-org/polkit
source=https://github.com/polkit-org/polkit/archive/refs/tags/127.tar.gz
sha256=9b7bc16f086479dcc626c575976568ba4a85d34297a750d8ab3d2e57f6d8b988

# Daemon package, dual-init: upstream systemd unit ships (path pinned
# to /usr/lib/systemd/system), OpenRC service added here, neither
# auto-enabled. Upstream setuid-root helpers (pkexec,
# polkit-agent-helper-1, 04755) are polkit's canonical privilege model
# (shadow-helpers precedent), staged by its own install script.
# session_tracking=logind (libsystemd in tree; ConsoleKit/elogind
# absent), authfw=pam (linux-pam in tree). introspection off: no
# introspection consumers (fwupd needs the libs, not the gir data).
# gettext/tests/examples/man at upstream defaults (off).
depends="dbus glib linux-pam"
# duktape (JS rules engine), expat (policy XML), dbus .pc for install
# paths, systemd-libs for logind tracking. pcre2/libffi/zlib close the
# glib .pc chain (libxslt precedent).
makedepends="binutils dbus-dev duktape-dev expat-dev gcc glib-dev libffi-dev linux-pam-dev make meson ninja pcre2-dev perl pkgconf systemd-dev zlib-dev"
subpackages="$pkgname-dev"

recipe_build() {
	POLKIT_BALL="$RECIPE_DIR/files/${pkgver}.tar.gz"
	echo "$sha256  $POLKIT_BALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$POLKIT_BALL"
	meson setup build "$SRC" \
		--prefix=/usr \
		-Dlibdir=lib \
		-Dsession_tracking=logind \
		-Dsystemdsystemunitdir=/usr/lib/systemd/system \
		-Dauthfw=pam \
		-Dpolkitd_user=polkitd \
		-Dpolkitd_uid=127 \
		-Dintrospection=false
	meson compile -C build
}

recipe_install() {
	DESTDIR="$PKGDEST" meson install -C build
	# OpenRC half of dual-init (never auto-enabled).
	install -D -m 0755 "$RECIPE_DIR/files/polkit.initd" \
		"$PKGDEST/etc/init.d/polkit"
	# Runtime identity declaration for the install-time reconciler
	# (polkitd:108; upstream sysusers fragment covers systemd).
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/polkit" \
		"$PKGDEST/usr/share/saphira/accounts.d/polkit"
}

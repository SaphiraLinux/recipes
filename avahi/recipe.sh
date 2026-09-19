#!/bin/sh

pkgname=avahi
pkgver=0.8
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Multicast DNS Service Discovery (SHAMPOO discovery foundation)"
license="LGPL-2.1-or-later"
origin=avahi
repo=saphira
url=https://github.com/avahi/avahi
source=https://github.com/avahi/avahi/releases/download/v0.8/avahi-${pkgver}.tar.gz
sha256=060309d7a333d38d951bc27598c677af1796934dbd98e1024e7ad8de798fedda
# NOTE(upstream): v0.8 (2020-02) is the newest upstream release at
# packaging time (the lathiat/avahi tree moved to the avahi/avahi org
# with no new release). The canonical releases URL above serves the
# identical bytes as the old org path (hash-verified); the old path is
# a redirect and is not pinned.

depends="
    dbus
    expat
    glib
    libdaemon
"

makedepends="
    dbus-dev
    expat-dev
    gcc
    gettext
    glib-dev
    libdaemon-dev
    libffi-dev
    make
    pcre2-dev
    pkgconf
    systemd-dev
"
# pcre2-dev is not a direct avahi input: glib-2.0.pc Requires
# libpcre2-8, so avahi's configure-time pkg-config probe fails without
# it in the sysroot (proven by the first build attempt: "Package
# 'libpcre2-8', required by 'glib-2.0', not found"). libffi-dev is the
# same edge one level deeper (gobject-2.0.pc Requires libffi - second
# attempt), systemd-dev one level deeper still (dbus-1.pc Requires
# libsystemd - third attempt; the dbus recipe's own init-coupling
# comment documents the libsystemd link). The .pc scan terminates
# there (libsystemd/libpcre2-8/libffi/expat carry no further
# Requires). No in-tree glib/dbus consumer declares any of these -
# every one of them is an unpublished FAILED workspace - so all three
# edges are declared here, explicitly, until *-dev packages carry
# their own .pc closures (separate systemic proposal, not smuggled
# into this recipe).

subpackages="
    $pkgname-dev
    $pkgname-doc
"

recipe_build()
{
	cd "$SRC"
	# Split-/run invariant (proven by payload inspection of the first
	# successful build: an empty top-level /run shipped, and the
	# daemon socket compiled to /run/avahi-daemon/socket): upstream
	# hardcodes avahi_runtime_dir="/run", ignoring localstatedir.
	# One variable feeds the socket macro, the install mkdir, and the
	# chroot helper alike - see files/avahi-saphira-runstatedir.patch.
	patch -p1 < "$RECIPE_DIR/files/avahi-saphira-runstatedir.patch"
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	"$SRC/configure" \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--libdir=/usr/lib \
		--disable-static \
		--with-xml=expat \
		--with-avahi-user=avahi \
		--with-avahi-group=avahi \
		--with-autoipd-user=avahi \
		--with-autoipd-group=avahi \
		--with-avahi-priv-access-group=avahi \
		--with-dbus-sys=/usr/share/dbus-1/system.d \
		--with-dbus-system-socket=unix:path=/var/run/dbus/system_bus_socket \
		--with-distro=none \
		--without-systemdsystemunitdir \
		--disable-gtk \
		--disable-gtk3 \
		--disable-qt4 \
		--disable-qt5 \
		--disable-mono \
		--disable-monodoc \
		--disable-python \
		--disable-pygobject \
		--disable-python-dbus \
		--enable-introspection=no \
		--disable-manpages \
		--disable-xmltoman \
		--disable-gdbm \
		--disable-libevent \
		--enable-glib \
		--enable-gobject \
		--enable-autoipd \
		--enable-compat-libdns_sd \
		--enable-compat-howl
	# Flag notes (all verified against configure --help in 0.8):
	# - --with-dbus-system-socket is the live option name (the --help
	#   text shows --with-dbus-system-address, which configure rejects
	#   as unrecognized - proven in scratch). The value carries the
	#   split-/run path (dbus r7 moved the socket; the stale /run
	#   default would silently disconnect discovery).
	# - No --disable-qt3/--disable-libcap/--disable-dbm/--disable-
	#   introspection exist; qt3 has no enable path without Qt3
	#   present, dbm defaults off, introspection takes =no.
	# - libevent integration is disabled for a minimal deterministic
	#   closure (no in-tree consumer); re-enabling it wants the flag
	#   flip plus the upstream .pc Requires fix (libevent-2.1.5 is a
	#   .pc name no libevent ships).
	# - libcap has no configure knob (auto-detected); it is
	#   deliberately absent from the closure, so the daemon drops
	#   privilege by setuid, deterministically.
	make
}

recipe_install()
{
	cd "$BUILDDIR"
	DESTDIR="$PKGDEST" make install
	# Dual-init policy (dbus precedent): the OpenRC counterpart ships
	# from files/ - neither init wraps the other, nothing auto-enabled.
	install -D -m 0755 "$RECIPE_DIR/files/avahi-daemon.initd" \
		"$PKGDEST/etc/init.d/avahi-daemon"
	# FHS declaration: avahi-daemon owns its runtime dir; makepkg
	# runs ensure-fhs after ensure-identity on install/upgrade.
	install -D -m 0644 "$RECIPE_DIR/files/fhs.d/avahi" \
		"$PKGDEST/usr/share/saphira/fhs.d/avahi"
	# Runtime identity declaration: avahi:70 (fixed). makepkg
	# generates the install scripts from this fragment; the package
	# creates its identity at install time. UID/GID 70 freeness
	# audit: absent from the base seed, absent from every other
	# accounts.d fragment, and upstream claims no fixed ID (its own
	# sysusers.d fragment asks for a dynamic _avahi, which Saphira
	# deliberately replaces - nothing here invokes
	# systemd-sysusers). UID 70 sits in the preferred 0..199
	# packaged range - never reuse it for another identity.
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/avahi" \
		"$PKGDEST/usr/share/saphira/accounts.d/avahi"
}

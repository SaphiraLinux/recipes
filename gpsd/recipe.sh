#!/bin/sh

pkgname=gpsd
pkgver=3.27.5
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="GPS daemon, libraries, and text-mode clients (cgps, gpsmon, gpspipe)"
license="BSD-2-Clause"
origin=gpsd
repo=main
url=https://gpsd.io/
# Canonical primary download.savannah.nongnu.org serves 502/504 from this
# network; the Savannah mirror carries byte-identical releases and is the
# URL fetched, extracted, and hashed for the pin below.
vendor=https://download-mirror.savannah.gnu.org/releases/gpsd/gpsd-3.27.5.tar.xz
sha256=dc4a62bad835282bae788772bc7cc8f8bec4c7a48e8dceeb37477a89091c4656

# Runtime: ncurses (cgps/gpsmon), libusb (non-serial USB receivers;
# serial/ACM receivers like u-blox need only the kernel cdc_acm driver),
# dbus (fix export), python3 (gpsfake, ubxtool, gpscat and other tools).
depends="
    dbus
    libusb
    ncurses
    python3
"

makedepends="
    dbus-dev
    gcc
    libusb-dev
    ncurses-dev
    pkgconf
    python3
    scons
"

# No systemd unit (Saphira is OpenRC; the init script below is the
# service), no X/Qt clients, no BlueZ (no bluetooth stack packaged), no
# generated man pages (asciidoctor not packaged - same deferral as
# chrony). Everything else stays at upstream defaults: all protocol
# drivers (including u-blox/UBX and NMEA), shared-memory export for
# chrony, control socket for hotplug, C++ bindings, Python tools.
# recipe.sh is also sourced in a minimal probe sandbox (no coreutils), so
# parallelism is added at the call sites, not in this variable.
scons_options="
    prefix=/usr
    bindir=bin
    sbindir=sbin
    libdir=lib
    sysconfdir=/etc
    rundir=/run
    systemd=false
    dbus_export=true
    bluez=false
    qt=false
    xgps=false
    python=true
    target_python=python3
    python_shebang='/usr/bin/env python3'
    manbuild=no
    gpsd_user=nobody
    gpsd_group=nobody
    udevdir=/lib/udev
"

recipe_build()
{
	# Local archive wins when present (verified, never re-downloaded);
	# otherwise build from the builder-verified $SOURCE_ARCHIVE. The
	# builder pre-extracted the fetch to $SRC; re-extracting identical
	# bytes is a harmless no-op, and the local path needs the extract.
	GPSBALL="$RECIPE_DIR/files/gpsd-3.27.5.tar.xz"
	if [ -f "$GPSBALL" ]; then
		echo "$sha256  $GPSBALL" | sha256sum -c -
	else
		[ -n "${SOURCE_ARCHIVE-}" ] && [ -f "$SOURCE_ARCHIVE" ] \
			|| { echo "ERROR: no local gpsd-3.27.5.tar.xz and no fetched SOURCE_ARCHIVE" >&2; return 1; }
		GPSBALL=$SOURCE_ARCHIVE
	fi
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$GPSBALL"
	cd "$SRC"
	# Saphira has no dialout group, so the daemon drops to nobody:nobody
    # (both exist as 65534); devices are opened as root before the drop,
    # and /dev/gpsN symlinks plus GROUP come from 25-gpsd.rules.
    scons -j${JOBS:-$(nproc)} $scons_options
}

recipe_install()
{
    DESTDIR="$PKGDEST" scons $scons_options install
    # udev rules (25-gpsd.rules, incl. 1546:01a7 u-blox 7 on cdc_acm) plus
    # the gpsd.hotplug helper; file copies only, no daemon reload.
    DESTDIR="$PKGDEST" scons $scons_options udev-install
    install -D -m 0755 "$RECIPE_DIR/files/gpsd.initd" \
        "$PKGDEST/etc/init.d/gpsd"
    install -D -m 0644 "$RECIPE_DIR/files/gpsd.confd" \
        "$PKGDEST/etc/conf.d/gpsd"
}

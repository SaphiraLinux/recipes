#!/bin/sh

pkgname=gpsd
pkgver=3.27.5
pkgrel=1
# Initial publication. Dedicated
# gpsd:176 service identity (Saphira owns its identity via accounts.d;
# Alpine's lack of one is their packaging choice, not ours), headers in
# gpsd-dev, Python bindings/tools in gpsd-python, full KPPS via
# pps-tools-dev (never knowingly ship degraded PPS when GPS/PPS
# timekeeping is an intended use), explicit SCons pins, control socket
# at /var/run/gpsd/gpsd.sock (scons rundir=; /var/run and /run are
# separate real trees), systemd unit fixed to /var/run
# (RuntimeDirectory= was the wrong tree). libgps ships in main by
# policy: install gpsd and get a working GPS service - daemon,
# executables, runtime libraries, configuration, both init services.
# No standalone gpsd-libs (a fresh main->own-libs edge is unplannable:
# resolvepkg self-hosting resolves via the repository; -dev/-doc
# auto-splits are a different operation from a dependency-resolved
# -libs package, and the distinction stands).
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="GPS daemon, libraries, and clients (gpspipe, gpsmon, cgps, gpsctl, gpscat)"
license="BSD-2-Clause"
origin=gpsd
repo=main
url=https://gpsd.io/
# Canonical primary download.savannah.nongnu.org serves 502/504 from this
# network; the Savannah mirror carries byte-identical releases and is the
# URL fetched, extracted, and hashed for the pin below.
vendor=https://download-mirror.savannah.gnu.org/releases/gpsd/gpsd-3.27.5.tar.xz
sha256=dc4a62bad835282bae788772bc7cc8f8bec4c7a48e8dceeb37477a89091c4656

# Main carries the daemon + C clients + libgps: one install is a
# working service, no dependency maze. Headers travel in gpsd-dev,
# Python modules/tools in gpsd-python (which carries the python3 edge).
# Legitimate external deps stay declared: ncurses (cgps/gpsmon),
# libusb (non-serial USB receivers; serial/ACM receivers like u-blox
# need only the kernel cdc_acm driver), dbus (fix export).
depends="
    dbus
    libusb
    ncurses
"

makedepends="
    dbus-dev
    gcc
    libusb-dev
    ncurses-dev
    pkgconf
    pps-tools-dev
    python3
    saphira-linux-uapi-headers
    scons
    systemd-dev
"

# gpsd-dev (headers, automatic usr/include split), gpsd-python
# (named split: files/split-gpsd-python.list).
subpackages="gpsd-dev gpsd-python"

# Dual-init policy: files/gpsd.initd and files/gpsd.service ship
# unconditionally and neither is enabled or started at install. The unit
# reads /etc/conf.d/gpsd through EnvironmentFile so $OPTIONS/$DEVICES
# expand exactly as they do for the init script, and it deliberately
# omits PrivateDevices (reading /dev/gps* is the daemon's whole purpose)
# and User= (gpsd opens devices as root, then setuid/setgid-drops to the
# compiled gpsd_user/gpsd_group itself). No X/Qt clients, no BlueZ (no
# bluetooth stack packaged), no generated man pages (asciidoctor not
# packaged - same deferral as chrony). Protocol drivers stay at upstream
# defaults (all on, including u-blox/UBX and NMEA); max_clients (64) and
# max_devices (6) stay default. Everything else is pinned explicitly so
# a missing build input fails here, never as a silent feature loss:
# - shm_export=true: shared-memory export for chrony (GPS timekeeping).
# - usb/ncurses/libgpsmm/shared/gpsd/gpsdclients/control_socket: on,
#   so gpspipe/gpsmon/cgps/gpsctl/libgps/ntpshmmon/ppscheck all build.
# - magic_hat=true: Linux PPS hack for Raspberry Pi et al.
# - timeservice=false: documented non-goal (dedicated time-appliance
#   build; ordinary daemon + SHM/PPS is the timekeeping path).
# - python_libdir pinned: unset, upstream rewrites /usr/lib to
#   /usr/local/lib (their FHS comment), which is the admin's tree, never
#   packaged payload. Pinned to python3.14's purelib - bump with python.
# - python_shebang deliberately UNSET: when target_python differs from
#   the default, upstream derives '/usr/bin/env python3' itself. Setting
#   it here broke the build - the space splits under the unquoted
#   $scons_options expansion into a phantom `python3'` file target.
# - systemd-dev: dbus-1.pc carries Requires.private libsystemd, and this
#   pkgconf fails the dbus probe without libsystemd.pc visible (proven
#   in scratch). Without it SCons silently turns dbus_export off. This
#   is the sanctioned libs-only edge (never full systemd); runtime stays
#   transitively covered via dbus -> systemd-libs.
# recipe.sh is also sourced in a minimal probe sandbox (no coreutils), so
# parallelism is added at the call sites, not in this variable.
scons_options="
    prefix=/usr
    bindir=bin
    sbindir=sbin
    libdir=lib
    sysconfdir=/etc
    rundir=/var/run/gpsd
    systemd=false
    dbus_export=true
    shm_export=true
    usb=true
    ncurses=true
    libgpsmm=true
    shared=true
    gpsd=true
    gpsdclients=true
    control_socket=true
    magic_hat=true
    timeservice=false
    bluez=false
    qt=false
    xgps=false
    python=true
    target_python=python3
    python_libdir=/usr/lib/python3.14/site-packages
    manbuild=no
    gpsd_user=gpsd
    gpsd_group=gpsd
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
	# Canonical tree first: the builder pre-extracts the fetch into $SRC
	# (unstripped) and SCons persists .scons-option-cache/.sconsign state
	# across runs in a reused workspace. A stale cache silently pins
	# options off (proven: a retained run's protocols went False from a
	# leftover cache). Wipe before extracting (scons-recipe precedent).
	find "$SRC" -mindepth 1 -delete
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$GPSBALL"
	cd "$SRC"
	# KPPS (RFC2783) is probed from sys/timepps.h, provided by
	# pps-tools-dev in the build root. Without it SCons degrades to
	# TIOCMIWAIT-only PPS with a mere notice - for a GPS-timekeeping
	# package that silent loss is unacceptable, so assert the header
	# before building rather than discovering the loss from the log.
	[ -f /usr/include/sys/timepps.h ] || {
		echo "ERROR: sys/timepps.h missing (pps-tools-dev); refusing degraded KPPS build" >&2
		return 1
	}
	# Saphira owns the gpsd identity (accounts.d/gpsd: 176); the daemon
	# opens its devices as root and drops to gpsd:gpsd itself. dialout
	# stays for device access (supplementary membership in the
	# fragment), never as the service identity.
	scons -j${JOBS:-$(nproc)} $scons_options
}

recipe_install()
{
	DESTDIR="$PKGDEST" scons $scons_options install
	# udev rules (25-gpsd.rules, incl. 1546:01a7 u-blox 7 on cdc_acm) plus
	# the gpsd.hotplug helper; file copies only, no daemon reload.
	DESTDIR="$PKGDEST" scons $scons_options udev-install
	# Service identity declaration (gpsd:176, supplementary dialout for
	# device access); makepkg reconciles it on install/upgrade.
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/gpsd" \
		"$PKGDEST/usr/share/saphira/accounts.d/gpsd"
	install -D -m 0755 "$RECIPE_DIR/files/gpsd.initd" \
		"$PKGDEST/etc/init.d/gpsd"
	install -D -m 0644 "$RECIPE_DIR/files/gpsd.service" \
		"$PKGDEST/usr/lib/systemd/system/gpsd.service"
	install -D -m 0644 "$RECIPE_DIR/files/gpsd.confd" \
		"$PKGDEST/etc/conf.d/gpsd"
	# FHS migration declaration (hotfix/var-packaging-bug-var-run-isnot-run):
	# gpsd:176 owns the corrected runtime dir; makepkg runs
	# ensure-fhs after ensure-identity on install/upgrade.
	install -D -m 0644 "$RECIPE_DIR/files/fhs.d/gpsd" \
		"$PKGDEST/usr/share/saphira/fhs.d/gpsd"
	# Payload proofs: the daemon, every promised C client, libgps, the
	# udev hookup, both init definitions, and both fragments. The -dev
	# (gps.h) and -python (gps modules) splits are partitioned by
	# buildpkg-single after install; the python module dir is asserted
	# here so a silent python_libdir drift breaks the build instead of
	# shipping an empty gpsd-python.
	for p in usr/sbin/gpsd usr/sbin/gpsdctl usr/bin/gpspipe \
		usr/bin/gpsmon usr/bin/cgps usr/bin/gpsctl \
		usr/bin/ntpshmmon usr/bin/ppscheck \
		lib/udev/rules.d/25-gpsd.rules lib/udev/gpsd.hotplug \
		etc/init.d/gpsd usr/lib/systemd/system/gpsd.service \
		etc/conf.d/gpsd usr/share/saphira/accounts.d/gpsd \
		usr/share/saphira/fhs.d/gpsd usr/lib/libgps.so \
		usr/include/gps.h \
		usr/lib/python3.14/site-packages/gps \
		usr/bin/gpscat; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: gpsd payload is missing $p" >&2
			return 1
		}
	done
}

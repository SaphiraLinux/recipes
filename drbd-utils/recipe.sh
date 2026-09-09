#!/bin/sh

pkgname=drbd-utils
pkgver=9.34.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="DRBD replicated-block management (drbdadm, drbdsetup, drbdmeta, drbdmon)"
license="GPL-2.0-or-later"
origin=drbd-utils
repo=saphira
url=https://linbit.com/drbd/
# Manages the in-tree 8.4 driver for two-node HA pairs today (v84 tools
# kept) and the out-of-tree 9.x driver (separate drbd-9 kmod recipe);
# drbd-utils 9.x covers 8.3/8.4/9.x drivers from one tree.
vendor=https://pkg.linbit.com/downloads/drbd/utils/drbd-utils-9.34.0.tar.gz
sha256=7063e6451056b6c51b1ab29e1a33321131286d11aeea3cb9f491458b3ca63dab

# Runtime: udev (/dev/drbd* nodes from the shipped rules), keyutils
# (TLS keyring integration, enabled at build).
depends="
    keyutils
    udev
"

makedepends="
    gcc
    keyutils-dev
    make
    pkgconf
    udev-dev
"

# No pacemaker/heartbeat/rgmanager (none packaged - failover is
# ldirectord's job); prebuilt mans (no docbook regen); keyring TLS on;
# 8.4 userland kept for the in-tree driver; no sysv/systemd scripts
# (OpenRC drbd.initd ships in files/). udevdir resolves via udev.pc to
# Saphira's /lib/udev - no hardcoded path.
drbd_options="
    --prefix=/usr
    --sysconfdir=/etc
    --localstatedir=/var
    --with-udev
    --without-pacemaker
    --without-heartbeat
    --without-rgmanager
    --without-bashcompletion
    --with-prebuiltman
    --with-keyutils
    --with-84support
    --with-initscripttype=none
"

recipe_build()
{
	# Local archive wins when present (verified, never re-downloaded);
	# otherwise build from the builder-verified $SOURCE_ARCHIVE (see
	# the gpsd recipe comment for why the re-extract is harmless).
	DRBDBALL="$RECIPE_DIR/files/drbd-utils-9.34.0.tar.gz"
	if [ -f "$DRBDBALL" ]; then
		echo "$sha256  $DRBDBALL" | sha256sum -c -
	else
		[ -n "${SOURCE_ARCHIVE-}" ] && [ -f "$SOURCE_ARCHIVE" ] \
			|| { echo "ERROR: no local drbd-utils-9.34.0.tar.gz and no fetched SOURCE_ARCHIVE" >&2; return 1; }
		DRBDBALL=$SOURCE_ARCHIVE
	fi
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$DRBDBALL"
	cd "$SRC"
	./configure $drbd_options
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	# Standard config skeleton, empty of resources: operator defines
	# pairs in /etc/drbd.d/. Upstream examples, installed as config.
	install -D -m 0644 "$SRC/scripts/drbd.conf" "$PKGDEST/etc/drbd.conf"
	install -D -m 0644 "$SRC/scripts/global_common.conf" \
		"$PKGDEST/etc/drbd.d/global_common.conf"
	install -D -m 0755 "$RECIPE_DIR/files/drbd.initd" \
		"$PKGDEST/etc/init.d/drbd"
}

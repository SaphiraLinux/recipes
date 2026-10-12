#!/bin/sh
pkgname=smartmontools
pkgver=7.5
pkgrel=4
# r4: merge line (explicit --localstatedir=/var adopted plus the real
# --with-systemdsystemunitdir=no parking upstream's unit - the hotfix
# --with-systemdsystemdir was not a smartmontools option; hatched
# publishes r3 built from different bytes, so the next revision).
# Payload change, bumps.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Control and monitor storage systems with S.M.A.R.T.'
license='GPL-2.0-or-later'
origin=smartmontools
repo=saphira
url=https://www.smartmontools.org/
smartmontools_sha256=690b83ca331378da9ea0d9d61008c4b22dde391387b9bbad7f29387f2595f76e
depends="gcc-libs"
makedepends="gawk gcc make"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/smartmontools-7.5.tar.gz"
	cd "$SRC"
	echo "$smartmontools_sha256  $RECIPE_DIR/files/smartmontools-7.5.tar.gz" | sha256sum -c -
	# --with-systemdsystemunitdir=no parks upstream's own unit; the house
	# unit is packaged instead, because smartd is a long-running S.M.A.R.T.
	# poller and shipping it with no service definition in either format
	# left it unstartable. The previous value, /no/systemd, pointed at a
	# path that does not exist on any system.
	./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
		--with-systemdsystemunitdir=no
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install	# Dual-init policy: both definitions ship unconditionally; neither is
	# enabled or started at install.
	install -D -m 0755 "$RECIPE_DIR/files/smartd.initd" \
		"$PKGDEST/etc/init.d/smartd"
	install -D -m 0644 "$RECIPE_DIR/files/smartd.service" \
		"$PKGDEST/usr/lib/systemd/system/smartd.service"
	[ -e "$PKGDEST/etc/init.d/smartd" ] || { echo "ERROR: smartmontools payload is missing etc/init.d/smartd" >&2; return 1; }
	[ -e "$PKGDEST/usr/lib/systemd/system/smartd.service" ] || { echo "ERROR: smartmontools payload is missing usr/lib/systemd/system/smartd.service" >&2; return 1; }

}

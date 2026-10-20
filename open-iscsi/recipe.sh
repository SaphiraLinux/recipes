#!/bin/sh

# open-iscsi: iSCSI initiator tools (iscsiadm for libvirt
# storage_iscsi; iscsid with dual-init units, never enabled).
# iSNS utilities need libisns and stay out of the default payload
# selection below (documented; libisns is packaged separately).

pkgname=open-iscsi
pkgver=2.1.13
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="iSCSI initiator tools (iscsiadm, iscsid)"
license="GPL-2.0-or-later"
origin=open-iscsi
repo=saphira
url=https://github.com/open-iscsi/open-iscsi
source=https://github.com/open-iscsi/open-iscsi/archive/refs/tags/${pkgver}.tar.gz
sha256=1c3a8ad7d86e57d247a08c013f5055ef695b3a07ed760d1aea7d90b9f9011602

# open-isns-dev carries libisns headers (hard -lisns link);
# openssl-dev carries libcrypto. NO_SYSTEMD=1: upstream systemd
# units are replaced by the hand-maintained pair below (packaged
# paths, /var/run, non-usrmerged). -DGLOB_ONLYDIR=0: musl has no
# glob_onlydir (Alpine aports main/open-iscsi, same 2.1.x era); by
# spec it is not guaranteed dirs-only anyway.
makedepends="
    binutils
    gcc
    make
    open-isns-dev
    openssl-dev
    pkgconf
"

recipe_build()
{
	CFLAGS="${CFLAGS-} -DGLOB_ONLYDIR=0" make -j${JOBS:-$(nproc)} \
		prefix=/usr \
		NO_SYSTEMD=1
}

recipe_install()
{
	make DESTDIR="$PKGDEST" \
		prefix=/usr \
		NO_SYSTEMD=1 \
		install_programs install_etc install_iname
	install -D -m 0644 "$SRC/COPYING" \
		"$PKGDEST/usr/share/licenses/open-iscsi/COPYING"
	install -D -m 0755 "$RECIPE_DIR/files/iscsid.initd" \
		"$PKGDEST/etc/init.d/iscsid"
	install -D -m 0644 "$RECIPE_DIR/files/iscsid.service" \
		"$PKGDEST/usr/lib/systemd/system/iscsid.service"
	for p in usr/sbin/iscsiadm usr/sbin/iscsid \
		etc/init.d/iscsid \
		usr/lib/systemd/system/iscsid.service; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: open-iscsi payload is missing $p" >&2
			return 1
		}
	done
}

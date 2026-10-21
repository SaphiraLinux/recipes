#!/bin/sh

# open-iscsi: iSCSI initiator tools (iscsiadm for libvirt
# storage_iscsi; iscsid with dual-init units, never enabled).
# iSNS utilities need libisns and stay out of the default payload
# selection below (documented; libisns is packaged separately).

pkgname=open-iscsi
pkgver=2.1.13
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="iSCSI initiator tools (iscsiadm, iscsid)"
license="GPL-2.0-or-later"
origin=open-iscsi
repo=saphira
url=https://github.com/open-iscsi/open-iscsi
source=https://github.com/open-iscsi/open-iscsi/archive/refs/tags/${pkgver}.tar.gz
sha256=1c3a8ad7d86e57d247a08c013f5055ef695b3a07ed760d1aea7d90b9f9011602

# iscsid links -lisns unconditionally: the runtime needs
# open-isns present, not just its headers at build time.
depends="
	open-isns
"

# open-isns-dev carries libisns headers (hard -lisns link);
# openssl-dev carries libcrypto; kmod-dev carries libkmod.h;
# zlib-dev satisfies libkmod.pc. NO_SYSTEMD=1: upstream systemd
# units are replaced by the hand-maintained pair below (packaged
# paths, /var/run, non-usrmerged). -DGLOB_ONLYDIR=0: musl has no
# glob_onlydir (Alpine aports main/open-iscsi, same 2.1.x era); by
# spec it is not guaranteed dirs-only anyway. INSTALL=/bin/install:
# upstream hardcodes /usr/bin/install but Saphira coreutils ships
# it at /bin (non-usrmerged).
makedepends="
    autoconf
    automake
    binutils
    gcc
    kmod-dev
    libtool
    make
    open-isns-dev
    openssl-dev
    pkgconf
    util-linux-dev
    zlib-dev
    zstd-dev
"

recipe_build()
{
	CFLAGS="${CFLAGS-} -DGLOB_ONLYDIR=0" make -j${JOBS:-$(nproc)} \
		prefix=/usr \
		INSTALL=/bin/install \
		NO_SYSTEMD=1
}

recipe_install()
{
	make DESTDIR="$PKGDEST" \
		prefix=/usr \
		INSTALL=/bin/install \
		NO_SYSTEMD=1 \
		install_programs install_etc install_iname
	# libopeniscsiusr is its own upstream sub-build with no
	# install hook covered above: stage the versioned library
	# by hand (SONAME links included).
	for f in "$SRC"/libopeniscsiusr/libopeniscsiusr.so*; do
		[ -e "$f" ] || continue
		install -D -m 0755 "$f" \
			"$PKGDEST/usr/lib/$(basename "$f")"
	done
	install -D -m 0644 "$SRC/COPYING" \
		"$PKGDEST/usr/share/licenses/open-iscsi/COPYING"
	install -D -m 0755 "$RECIPE_DIR/files/iscsid.initd" \
		"$PKGDEST/etc/init.d/iscsid"
	install -D -m 0644 "$RECIPE_DIR/files/iscsid.service" \
		"$PKGDEST/usr/lib/systemd/system/iscsid.service"
	# Upstream SBINDIR is exec_prefix/sbin: admin tools land in
	# /sbin, which is correct under the non-usrmerged layout
	# (/sbin is its own tree, not an alias).
	for p in sbin/iscsiadm sbin/iscsid \
		usr/lib/libopeniscsiusr.so.0.2.0 \
		etc/init.d/iscsid \
		usr/lib/systemd/system/iscsid.service; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: open-iscsi payload is missing $p" >&2
			return 1
		}
	done
}

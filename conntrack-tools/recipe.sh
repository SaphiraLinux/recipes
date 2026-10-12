#!/bin/sh
pkgname=conntrack-tools
pkgver=1.4.9
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Connection tracking userspace tools (conntrack, conntrackd)'
license='GPL-2.0-or-later'
origin=conntrack-tools
repo=saphira
url=https://netfilter.org/projects/conntrack-tools/
conntrack_tools_sha256=c15afe488a8d408c9d6d61e97dbd19f3c591942f62c13df6453a961ca4231cae
depends="libmnl libnfnetlink libnetfilter_conntrack libnetfilter_queue libnetfilter_cttimeout libnetfilter_cthelper libtirpc"
makedepends="bison flex gawk gcc make pkgconf libmnl-dev libnfnetlink-dev libnetfilter_conntrack-dev libnetfilter_queue-dev libnetfilter_cttimeout-dev libnetfilter_cthelper-dev libtirpc-dev"
subpackages="$pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/conntrack-tools-1.4.9.tar.xz"
	cd "$SRC"
	echo "$conntrack_tools_sha256  $RECIPE_DIR/files/conntrack-tools-1.4.9.tar.xz" | sha256sum -c -
	./configure --prefix=/usr --sysconfdir=/etc --disable-static --localstatedir=/var
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install	# Dual-init policy: both definitions ship unconditionally; neither is
	# enabled or started at install.
	install -D -m 0755 "$RECIPE_DIR/files/conntrackd.initd" \
		"$PKGDEST/etc/init.d/conntrackd"
	install -D -m 0644 "$RECIPE_DIR/files/conntrackd.service" \
		"$PKGDEST/usr/lib/systemd/system/conntrackd.service"
	[ -e "$PKGDEST/etc/init.d/conntrackd" ] || { echo "ERROR: conntrack-tools payload is missing etc/init.d/conntrackd" >&2; return 1; }
	[ -e "$PKGDEST/usr/lib/systemd/system/conntrackd.service" ] || { echo "ERROR: conntrack-tools payload is missing usr/lib/systemd/system/conntrackd.service" >&2; return 1; }

}

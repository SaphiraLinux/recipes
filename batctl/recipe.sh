#!/bin/sh

pkgname=batctl
pkgver=2026.3
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='B.A.T.M.A.N. advanced control and management tool (batman-adv userspace)'
license='GPL-2.0-only'
origin=batctl
repo=saphira
url=https://www.open-mesh.org/projects/batctl/wiki
source=https://downloads.open-mesh.org/batman/releases/batman-adv-2026.3/batctl-2026.3.tar.gz
sha256=2c8443fae7b3471a500837f8cfbbc2b7bbab602e43ce8c61b100560dec1d9ee0

# batman-adv itself lives in the Saphira kernel (CONFIG_BATMAN_ADV=m on
# the 7.1.5/7.2.2/7.2.3 lines, BATMAN_V included): no out-of-tree module
# is packaged. This recipe is only the control tool, which works over
# both wired and wireless interfaces because batman-adv is layer 2.
# Upstream publishes a detached .asc signature beside the tarball; it is
# archived in files/ next to the source (recipe sha256= stays authoritative).
# batctl is a command-line tool, not a daemon: no service units and no
# service identity apply (it runs as the invoking user, conventionally
# root for netlink/raw-socket operations).
makedepends="
    gcc
    libnl-dev
    make
    pkgconf
"

recipe_build()
{
	make -C "$SRC" PREFIX=/usr
}

recipe_install()
{
	make -C "$SRC" PREFIX=/usr DESTDIR="$PKGDEST" install
	install -D -m 0644 "$SRC/README.rst" \
		"$PKGDEST/usr/share/doc/batctl/README.rst"
}

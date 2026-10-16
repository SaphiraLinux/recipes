#!/bin/sh

pkgname=acpid
pkgver=2.0.34
# r1: initial Saphira port. ACPI power-button handling for OpenRC
# targets (systemd targets use logind as the single event owner and
# leave this installed but disabled). Listens on netlink/input-layer
# events; the shipped power-button rule runs /sbin/poweroff.
pkgrel=2
# r2: supervise the foreground daemon like sshd (a foreground
# command in plain start() never returns and openrc-run SIGKILLs it
# on timeout - proven by acpid marked failed every boot).
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="ACPI event daemon (power button handling)"
license="GPL-2.0-or-later"
origin=acpid
repo=main
url=https://sourceforge.net/projects/acpid2/
source=https://downloads.sourceforge.net/acpid2/acpid-2.0.34.tar.xz
sha256=2d095c8cfcbc847caec746d62cdc8d0bff1ec1bc72ef7c674c721e04da6ab333

depends=""

makedepends="
    gcc
    make
"

recipe_build()
{
	# musl has no stat64/fstat64 (off_t is already 64-bit).
	patch -d "$SRC" -Np1 -i "$RECIPE_DIR/files/saphira-musl-stat.patch"
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var
	make
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	# Power-button rule: the only event the base image handles.
	# /sbin/poweroff is OpenRC's own halt path, absolute by policy.
	install -D -m 0644 "$RECIPE_DIR/files/acpi/events/powerbtn" \
		"$PKGDEST/etc/acpi/events/powerbtn"
	install -d -m 0755 "$PKGDEST/etc/init.d" "$PKGDEST/usr/lib/systemd/system"
	install -m 0755 "$RECIPE_DIR/files/acpid.initd" \
		"$PKGDEST/etc/init.d/acpid"
	install -m 0644 "$RECIPE_DIR/files/acpid.service" \
		"$PKGDEST/usr/lib/systemd/system/acpid.service"
}

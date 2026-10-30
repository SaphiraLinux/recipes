#!/bin/sh

pkgname=cups
pkgver=2.4.20
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="OpenPrinting CUPS printing system (scheduler, client tools, libcups)"
license="Apache-2.0"
origin=cups
repo=main
url=https://openprinting.github.io/cups/
vendor=https://github.com/OpenPrinting/cups/releases/download/v2.4.20/cups-2.4.20-source.tar.gz
sha256=ab4d9cd7f3e58060091d2b24972223d6401675f11c49b65abf4f6ef31dea22ff

# JDK 17 links libcups (printing) and the scheduler serves LAN
# printers: full components, not libcups-only. Runtime edges are
# DT_NEEDED providers (libcups, backends, notifier); gzip is an exec
# dep for compressed PPDs. RUNTIME gate verifies the linkage.
depends="
    acl
    avahi
    dbus
    gzip
    libusb
    linux-pam
    openssl
    zlib
"

makedepends="
    acl-dev
    avahi-dev
    binutils
    dbus-dev
    gcc
    gzip
    libusb-dev
    linux-pam-dev
    make
    openssl-dev
    pkgconf
    zlib-dev
"

subpackages="
    $pkgname-dev
    $pkgname-doc
"

# Server on purpose (operator direction 2026-10-29: CUPS + cupsd are
# wanted; X client libs allowed, desktop env never). Non-negotiable
# upstream facts, verified against the vendored configure macros:
# NEEDS_LIB_CUPS and NEEDS_LIB_ALSA are true on every non-Windows
# target (libraries.m4) and --with-cups=no/--with-alsa=no are refused
# by the macros, so the JDK chain genuinely needs these ports.
# Explicit selections over autodetection:
# --with-tls=openssl (openssl-dev published; gnutls is not in the
# universe, cdsa is macOS-only).
# --with-dnssd=avahi (avahi-dev published; mdnsresponder is not).
# --enable-libusb (libusb-dev published; USB printers are in scope).
# --with-pam-module=unix (deterministic PAMMOD regardless of which
# /etc/pam.d probe files the namespace carries; pambase ships
# system-auth so PAMDIR resolves).
# --with-systemd=/usr/lib/systemd/system installs the unit files to
# the destination-system path; libsystemd itself is deliberately NOT
# linked (no systemd makedepend: socket activation without
# enablement is dead code plus a runtime edge; units ship inert).
# --with-rcdir=no (upstream SysV script is never installed; Saphira
# ships its own OpenRC init.d instead).
# --with-cups-user=lp --with-cups-group=lp --with-system-groups=lpadmin
# pin the daemon identity deterministically (never probed from the
# namespace /etc/passwd); lp group 8 is seed-owned, lp user 179 and
# lpadmin group 180 are minted in accounts.tsv.
# Left at upstream defaults with reasons: dbus notifier on (dbus-dev
# published), ACL probe on (acl-dev published), zlib on (required),
# browsing/webif/shared on (runtime cupsd.conf choices, not build
# choices), languages all (capability preserved), gssapi off (opt-in
# upstream, explicitly deprecated by upstream, no krb5 provider),
# libpaper off (opt-in upstream, no provider in universe),
# tcp-wrappers off (opt-in upstream, deprecated mechanism, no
# provider), static libs off (shared-only payloads).
recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/cups-2.4.20-source.tar.gz" | sha256sum -c -
	rm -rf "$BUILDDIR" && mkdir -p "$BUILDDIR"
	tar --no-same-owner -xf "$RECIPE_DIR/files/cups-2.4.20-source.tar.gz" \
		-C "$BUILDDIR" --strip-components=1
	cd "$BUILDDIR"
	# layout baseline: --prefix=/usr --sysconfdir=/etc
	# --localstatedir=/var (explicit, never inherited). libdir stays
	# /usr/lib (no /usr/lib64 on Saphira, probed correctly); server
	# binaries land in /usr/lib/cups, state in /var/* by default.
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--with-cups-user=lp \
		--with-cups-group=lp \
		--with-system-groups=lpadmin \
		--with-tls=openssl \
		--with-dnssd=avahi \
		--enable-libusb \
		--with-pam-module=unix \
		--with-systemd=/usr/lib/systemd/system \
		--with-rcdir=no
	make
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	# Dual init, both inert until enabled: OpenRC script is
	# Saphira-written (files/), systemd units are upstream-generated
	# (already at destination-system paths via --with-systemd).
	install -D -m 0755 "$RECIPE_DIR/files/cups.initd" \
		"$PKGDEST/etc/init.d/cups"
	# Service identity declaration (lp user 179, seed lp group 8,
	# lpadmin group 180 for SystemGroup); makepkg generates the
	# install/upgrade scripts ONLY from this payload copy. State
	# dirs are created/reconciled at install time, never shipped as
	# payload residue.
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/cups" \
		"$PKGDEST/usr/share/saphira/accounts.d/cups"
	# Rotation fragment (logrotate.d convention): upstream ships no
	# fragment and cupsd's HUP log-reopen is unverified, so
	# copytruncate rather than signalling a print daemon on a guess.
	install -D -m 0644 "$RECIPE_DIR/files/logrotate.d/cups" \
		"$PKGDEST/etc/logrotate.d/cups"
	# Payload proof: every load-bearing path asserted, so a dropped
	# install target or a skipped unit fails the build instead of
	# shipping a scheduler that cannot start or be observed.
	for p in usr/sbin/cupsd \
		etc/cups/cupsd.conf \
		etc/cups/cups-files.conf \
		etc/pam.d/cups \
		etc/init.d/cups \
		usr/lib/systemd/system/cups.service \
		usr/lib/systemd/system/cups.socket \
		usr/lib/systemd/system/cups.path \
		usr/lib/cups/backend/usb \
		usr/lib/libcups.so \
		usr/share/saphira/accounts.d/cups \
		etc/logrotate.d/cups; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: cups payload is missing $p" >&2
			return 1
		}
	done
}

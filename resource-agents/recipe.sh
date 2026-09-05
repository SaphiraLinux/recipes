#!/bin/sh

pkgname=resource-agents
pkgver=4.18.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='ClusterLabs resource agents: OCF agents and ldirectord (Layer 4 load balancer director with IPv6 support)'
license='GPL-2.0-or-later AND LGPL-2.1-or-later'
origin=resource-agents
repo=saphira
url=https://github.com/ClusterLabs/resource-agents
source=https://github.com/ClusterLabs/resource-agents/archive/refs/tags/v${pkgver}.tar.gz
sha256=2570e473a8693ae36f130aa3edfddba0300b12c8897aaa4ce0af87aa2afca9d4

# Saphira patch series for ldirectord (authored against v4.18.0, whose
# ldirectord/ldirectord.in is byte-identical to master 6c50a9b):
#
# 0001: Socket6 is optional - modern Perl core Socket provides the whole
#       API; the core getaddrinfo()/getnameinfo() die() on error while
#       Socket6 returns error strings, so all call sites are eval-wrapped
#       and family hints are passed per backend. Saphira's perl has no
#       Socket6, so upstream ldirectord cannot even compile there.
# 0002: every non-core check module (LWP chain, Net::LDAP, Net::IMAP::*,
#       Mail::POP3Client, Net::DNS, DBI, Authen::Radius, IO::Socket::INET6,
#       Mail::Send) degrades gracefully: HTTP negotiate falls back to the
#       core HTTP::Tiny module, everything else to a connect check, email
#       alerts are skipped - instead of dying and reporting false DOWNs.
# 0003: IPv6 parsing hardening - bracket-aware host:port splitting in
#       parse_fallback()/ld_gethostservbyname() (bare or unbracketed IPv6
#       is no longer silently mangled into a truncated address plus a
#       bogus port) and ld_start() never dereferences the undefined
#       ipvsadm readback of a not-yet-created virtual service.
#
# FWM/IPv6 firewall-mark behaviour was validated against Saphira ipvsadm
# 1.31: -f <mark> [-6] ordering, large marks (2000000+), the " IPv6"
# readback marker mapping to the fwm6 key, and bracketed IPv6 real
# servers all parse with exact config-side key parity. ldirectord never
# needs to resolve a mark to an address; the mark->VIP mapping is
# operator nftables configuration.

depends="ipvsadm"
makedepends="
	autoconf
	automake
	gcc
	glib-dev
	libqb-dev
	make
	pkgconf
"

subpackages="$pkgname-doc"

recipe_build()
{
	for p in "$RECIPE_DIR"/files/0*.patch; do
		patch -d "$SRC" -Np1 -i "$p"
	done
	( cd "$SRC" && autoreconf -fi )
	mkdir -p "$BUILDDIR"
	cd "$BUILDDIR"
	../source/configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--with-initdir=/etc/init.d \
		--with-ocf-root=/usr/lib/ocf \
		--with-pkg-name=Saphira
	# ldirectord is the payload Saphira consumes; the heartbeat C agents
	# and the doxygen/doc man page tree are deliberately not built.
	make -C ldirectord -j${JOBS:-$(nproc)}
	# Saphira perl has no Socket6 and no LWP chain: the generated script
	# must compile with the core-module fallbacks and carry the patches.
	perl -c "$BUILDDIR/ldirectord/ldirectord"
	grep -q 'HTTP::Tiny fallback' "$BUILDDIR/ldirectord/ldirectord"
	grep -q 'HAVE_SOCKET6' "$BUILDDIR/ldirectord/ldirectord"
}

recipe_install()
{
	make -C "$BUILDDIR/ldirectord" DESTDIR="$PKGDEST" install
	# Dual-init policy: ldirectord is a genuine long-running daemon and
	# already ships its OpenRC form (upstream installs the ldirectord
	# script itself as /etc/init.d/ldirectord); the systemd counterpart
	# ships from files/.  Neither wraps the other, nothing auto-enabled.
	install -D -m 0644 "$RECIPE_DIR/files/ldirectord.service" \
		"$PKGDEST/usr/lib/systemd/system/ldirectord.service"
}

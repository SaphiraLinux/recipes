#!/bin/sh

# LLDP daemon for link-layer neighbor visibility. Runs as root by
# upstream default; privilege separation to _lldpd is declared and
# configured (--with-privsep-*) so the identity exists from first
# install, with the data directory owned accordingly.

# r2: move the privilege-separation identity _lldpd off 124, which is
# hostapd's and published; one package owns each declared identity. 124 -> 147.
# lldpd was unpublished, so no migration and no legacy sidecar.
# r2 (hotfix/var-packaging-bug-var-run-isnot-run): home/dir /run/lldpd ->
# /var/run/lldpd with fhs.d migration (the daemon defaults were always
# /var/run via GNU runstatedir; only the fragment was wrong).
# r3: merge line (both parents shipped different r2 payloads): 147
# identity, dual-init service definitions with payload proofs, and the
# fhs.d migration declaration. Payload change, revision bumps.
pkgname=lldpd
pkgver=1.0.22
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="LLDP daemon for link-layer discovery"
license="ISC"
origin=lldpd
repo=saphira
url=https://lldpd.github.io/
source=https://github.com/lldpd/lldpd/releases/download/1.0.22/lldpd-1.0.22.tar.gz
sha256=552baa55118bccbcd1e61c51db438930a36ce04e0abd84c4c0b7b20633ca2b5a

depends="
    libevent
    libmd
    readline
"

makedepends="
    binutils
    gcc
    libbsd-dev
    libevent-dev
    libmd-dev
    make
    pkgconf
    readline-dev
"
# libbsd-dev: musl ships no sys/queue.h. libmd-dev + libmd: the
# libbsd overlay links -lbsd -lmd (config.log evidence).

recipe_build()
{
	./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
		--with-readline --without-xml \
		--with-privsep-user=_lldpd --with-privsep-group=_lldpd
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	# Runtime identity declaration: _lldpd:147 for privilege
	# separation (matches the configure --with-privsep-* user/group
	# and the default chroot/run directory).
	# r2: home/dir /run/lldpd -> /var/run/lldpd (the daemon defaults
	# were always /var/run via GNU runstatedir; only the fragment
	# was wrong). Payload change, revision bumps.
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/lldpd" \
		"$PKGDEST/usr/share/saphira/accounts.d/lldpd"
	# Dual-init policy: both definitions ship unconditionally; neither is
	# enabled or started at install.
	install -D -m 0755 "$RECIPE_DIR/files/lldpd.initd" \
		"$PKGDEST/etc/init.d/lldpd"
	install -D -m 0644 "$RECIPE_DIR/files/lldpd.service" \
		"$PKGDEST/usr/lib/systemd/system/lldpd.service"
	# Identity exists (files/accounts.d/lldpd declares _lldpd:147) but
	# before this there was no way to start the daemon, so the identity
	# was provisioned and never used.
	for p in etc/init.d/lldpd usr/lib/systemd/system/lldpd.service; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: lldpd payload is missing $p" >&2
			return 1
		}
	done
	# The unit must not pin User=: lldpd does its own privsep from root.
	grep -qE '^User=' "$RECIPE_DIR/files/lldpd.service" && {
		echo "ERROR: lldpd.service must not set User=; lldpd drops privileges itself" >&2
		return 1
	}
	# FHS migration declaration (hotfix/var-packaging-bug-var-run-isnot-run):
	# _lldpd:147 owns the corrected runtime dir; makepkg runs
	# ensure-fhs after ensure-identity on install/upgrade.
	install -D -m 0644 "$RECIPE_DIR/files/fhs.d/lldpd" \
		"$PKGDEST/usr/share/saphira/fhs.d/lldpd"
	return 0
}

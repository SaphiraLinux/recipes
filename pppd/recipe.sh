pkgname=pppd
pkgver=2.4.5
pkgrel=6
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='PPP daemon (wkz musl-era fork of ppp 2.4.5) with rp-pppoe plugin; PAP/CHAP-MD5 auth'
license='BSD-3-Clause/GPL-2.0-or-later'
origin=pppd
repo=saphira
url=https://github.com/wkz/pppd
source=https://codeload.github.com/wkz/pppd/tar.gz/refs/heads/master
sha256=4aeab09185d4b9f67c65263615fa7d88645c235434d78ba6bd11d4e81909759e

# Classification (dual-init audit 2026-09-03): pppd is NOT a service
# package.  It is a set of executables/helpers invoked for a configured
# peer/session (pon/poff + chat scripts); no always-on init services are
# invented for it merely to satisfy the audit.  Operators script pppd
# sessions explicitly.

depends="libxcrypt"
makedepends="
	binutils
	gcc
	libxcrypt-dev
	saphira-kernel-headers=7.1.5
	make
"

# musl-native build notes (no glibc shims, ever):
#   - -std=gnu99: pppd.h 'typedef int bool' predates C23
#   - -include time.h: bundled include/net/ppp_defs.h uses time_t without it
#   - CHAPMS/MPPE off: 2.4.5's pppcrypt needs libc setkey/encrypt (glibc) or
#     libdes (dead); Saphira libxcrypt ships neither. UK PPPoE uses PAP/CHAP.
#     Re-enable only with an openssl-EVP pppcrypt backport.
#   - IPX_CHANGE dropped: linux/ipx.h removed in modern kernel headers
#   - FILTER (libpcap) disabled until libpcap is packaged
#   - seds run BEFORE ./configure: classic configure bakes Makefile.linux
#     into pppd/Makefile at generation time.
#   - patches/ppp-2.4.5-plugin-musl.patch: bundled rp-pppoe plugin
#     (sys/cdefs.h, ethhdr include order, unused if_pppox include).
recipe_build()
{
	cd "$SRC"
	rm -f include/linux/if_pppol2tp.h  # stale bundled header shadows system uapi
	sed -i 's/-DIPX_CHANGE //; s/^FILTER=y/# FILTER=y/; s/^CHAPMS=y/# CHAPMS=y/; s/^MPPE=y/# MPPE=y/' pppd/Makefile.linux
	./configure --prefix=/usr
	make -j${JOBS:-$(nproc)} -C pppd COPTS="-O2 -pipe -Wall -g -std=gnu99 -include time.h"
	make -j${JOBS:-$(nproc)} -C chat COPTS="-O2 -pipe -Wall -g -std=gnu89"
	make -j${JOBS:-$(nproc)} -C pppstats COPTS="-O2 -pipe -Wall -g -std=gnu89"
	make -j${JOBS:-$(nproc)} -C pppd/plugins/rp-pppoe COPTS="-O2 -pipe -Wall -g -std=gnu99"
}

# Classic ppp 2.4.5 has no DESTDIR-aware install; manual placement.
recipe_install()
{
	install -d "$PKGDEST/usr/sbin" "$PKGDEST/usr/include/pppd" \
		"$PKGDEST/usr/lib/pppd/2.4.5" "$PKGDEST/etc/ppp" \
		"$PKGDEST/usr/share/man/man8"
	install -m 755 "$SRC/pppd/pppd" "$PKGDEST/usr/sbin/pppd"
	install -m 755 "$SRC/chat/chat" "$PKGDEST/usr/sbin/chat"
	install -m 755 "$SRC/pppstats/pppstats" "$PKGDEST/usr/sbin/pppstats"
	install -m 644 "$SRC/pppd/plugins/rp-pppoe/rp-pppoe.so" \
		"$PKGDEST/usr/lib/pppd/2.4.5/pppoe.so"
	for h in "$SRC/pppd"/*.h; do
		install -m 644 "$h" "$PKGDEST/usr/include/pppd/"
	done
	install -d "$PKGDEST/usr/include/net"
	for h in "$SRC/include/net/ppp_defs.h" "$SRC/include/net/ppp-comp.h"; do
		[ -f "$h" ] && install -m 644 "$h" "$PKGDEST/usr/include/net/"
	done
	for m in "$SRC/pppd"/*.8 "$SRC/chat/chat.8"; do
		[ -f "$m" ] && install -m 644 "$m" "$PKGDEST/usr/share/man/man8/"
	done
	install -m 644 "$SRC/etc.ppp/options" "$PKGDEST/etc/ppp/options"
}

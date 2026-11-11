#!/bin/sh

pkgname=haproxy-systemd
pkgver=3.4.7
pkgrel=1
# systemd-optimized HAProxy variant (first publication is r1): the base
# haproxy recipe stays OpenRC-first and lean; this package carries the
# linkage that changes the runtime closure (Lua scripting, QUIC) and
# the systemd-native unit (Type=notify over -Ws master mode), and
# replaces the base so exactly one haproxy owns the paths. The
# replaces is bilateral by design (base names this package back):
# the ownership gate exempts each side only through its own line,
# so both recipes must keep theirs forever. Switching back is
# explicit: apk del haproxy-systemd && apk add haproxy.
# Upstream is byte-identical to haproxy 3.4.7 (sibling-vendored,
# sidecar-verified, never re-downloaded).
# Verified non-facts (do not regress):
# - no USE_SYSTEMD flag exists upstream: sd_notify is reimplemented
#   dependency-free in src/systemd.c, so notify needs no linkage -
#   only this unit. No systemd-libs link, no systemd header, nothing.
# - SPOE (the WAF hookup) is core with no flag; the filtering agent
#   itself is a separate daemon and a separate recipe, not this one.
# - QUIC rides USE_QUIC=1 + USE_QUIC_OPENSSL_COMPAT=1 against stock
#   OpenSSL (limited features per upstream); quictls proper is
#   unneeded. If a future upstream refuses this pairing, the compat
#   path goes first with the log as evidence, never a silent drop.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Reliable, high performance TCP/HTTP load balancer (systemd-optimized: notify, Lua, QUIC)'
license='GPL-2.0-or-later LGPL-2.1-or-later'
origin=haproxy
repo=saphira
url=https://www.haproxy.org/
# Sibling-vendored upstream (andrews-kernel pattern): same bytes the
# haproxy recipe vendors, verified twice - the pin below plus the
# sibling sidecar. Never re-downloaded, never trusted by path. If the
# base line moves on, this recipe fails closed here until it is
# deliberately rebased (same NVR, same source, same proof).
HAPROXY_SHA256=ccfd342f3724c2cd659574044d788f44e20b212467c6bd5edbbfc517a2775dca
depends="lua54 openssl pcre2 zlib"
makedepends="
	gcc
	libxcrypt-dev
	lua54-dev
	make
	openssl-dev
	pcre2-dev
	zlib-dev
"
replaces="haproxy"

recipe_build()
{
	HAPROXY_SIB="$RECIPE_DIR/../haproxy/files"
	HAPROXY_BALL="$HAPROXY_SIB/haproxy-3.4.7.tar.gz"
	[ -f "$HAPROXY_BALL" ] ||
		{ echo "ERROR: no sibling haproxy-3.4.7.tar.gz in $HAPROXY_SIB (rebase the variant)" >&2; return 1; }
	echo "$HAPROXY_SHA256  $HAPROXY_BALL" | sha256sum -c - ||
		{ echo "ERROR: sibling haproxy tarball failed the recipe pin" >&2; return 1; }
	(cd "$HAPROXY_SIB" && sha256sum -c "haproxy-3.4.7.tar.gz.sha256") ||
		{ echo "ERROR: sibling haproxy tarball failed its own sidecar" >&2; return 1; }
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$HAPROXY_BALL"
	cd "$SRC"
	# Same proven base set as haproxy, plus the variant closure: Lua
	# scripting, QUIC (+ stock-OpenSSL compat), kTLS, netns, TCP Fast
	# Open. All inert unless configured; the -vv proof below fails
	# the build if any flag is silently dropped.
	make -j${JOBS:-$(nproc)} \
		TARGET=linux-musl \
		USE_GETADDRINFO=1 \
		USE_KTLS=1 \
		USE_LUA=1 \
		USE_NS=1 \
		USE_OPENSSL=1 \
		USE_PCRE2=1 \
		USE_PCRE2_JIT=1 \
		USE_PROMEX=1 \
		USE_QUIC=1 \
		USE_QUIC_OPENSSL_COMPAT=1 \
		USE_SHM_OPEN=1 \
		USE_TFO=1 \
		USE_ZLIB=1

	# Identity + feature proof (SIGPIPE-safe grep -c, never -q under
	# pipefail): the binary must name HAProxy and carry the variant
	# features the linkage was built for. (+SYSTEMD is deliberately
	# not asserted: no such flag exists, notify is protocol, not
	# linkage - the unit carries it.)
	[ "$(./haproxy -vv | grep -ci '^HAProxy')" -gt 0 ] || {
		echo "ERROR: built haproxy does not identify itself" >&2
		return 1
	}
	for feat in '+LUA' '+QUIC'; do
		[ "$(./haproxy -vv | grep -F -c "$feat")" -gt 0 ] || {
			echo "ERROR: built haproxy lacks $feat (flag silently dropped?)" >&2
			return 1
		}
	done
}

recipe_install()
{
	make DESTDIR="$PKGDEST" PREFIX=/usr SBINDIR=/usr/sbin \
		DOCDIR=/usr/share/doc/haproxy install
	install -D -m 0644 "$RECIPE_DIR/files/haproxy.cfg" \
		"$PKGDEST/etc/haproxy/haproxy.cfg"
	install -D -m 0755 "$RECIPE_DIR/files/haproxy.initd" \
		"$PKGDEST/etc/init.d/haproxy"
	install -D -m 0644 "$RECIPE_DIR/files/haproxy.service" \
		"$PKGDEST/usr/lib/systemd/system/haproxy.service"
	install -d -m 0755 "$PKGDEST/var/lib/haproxy" "$PKGDEST/var/log/haproxy"
	test -x "$PKGDEST/usr/sbin/haproxy"
}

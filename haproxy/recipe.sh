#!/bin/sh

pkgname=haproxy
pkgver=3.4.7
pkgrel=1
# r3: upstream 3.4.7 (Nov 2026: remote-DoS CPU exhaustion via
# truncated H2 PING CVE-2026-110353 and chunked requests
# CVE-2026-110354, fixed in 3.4.6; take 3.4.7 which also carries
# the chunked-response regression fix). New upstream version:
# pkgrel resets to 1.
# r2: OpenRC-tracked pidfile /run/haproxy.pid -> /var/run/haproxy.pid;
# RuntimeDirectory=haproxy removed (created an unconsumed /run/haproxy
# dir - nothing ever referenced it). No fhs.d fragment by rule: no
# directory ever consumed, flat tmpfs pidfile needs no migration
# (document-and-leave, unbound precedent). Payload change, revision bumps.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Reliable, high performance TCP/HTTP load balancer'
license='GPL-2.0-or-later LGPL-2.1-or-later'
origin=haproxy
repo=saphira
url=https://www.haproxy.org/
# Bilateral replaces with haproxy-systemd: the two packages are
# alternative providers of the same paths (binary, units, config,
# docs), exactly one installed per machine. The ownership gate
# exempts each side only through its own replaces line, so BOTH
# recipes must keep theirs forever - removing either one fails the
# next publication with a dual-ownership collision. Switching is
# explicit: apk del one, apk add the other (installing over the
# other leaves it installed-but-shadowed; never --force-overwrite).
replaces="haproxy-systemd"
source=https://www.haproxy.org/download/3.4/src/haproxy-${pkgver}.tar.gz
sha256=ccfd342f3724c2cd659574044d788f44e20b212467c6bd5edbbfc517a2775dca

depends="pcre2 openssl zlib"
makedepends="
	gcc
	libxcrypt-dev
	make
	openssl-dev
	pcre2-dev
	zlib-dev
"

recipe_build()
{
	# Feature set (every USE_* reviewed against the 3.4.7 Makefile;
	# upstream marks most as Automatic). Enabled beyond the obvious:
	# TFO (TCP Fast Open, Linux only, no deps), NS (network namespaces,
	# no deps - matches the iproute2 netns convention), KTLS (kernel
	# TLS offload, Linux 4.17+, no deps). All three are inert unless
	# configured, so they are pure capability with no behavior change.
	# Deliberately NOT enabled, each with its reason:
	# - QUIC: needs the quictls API (stock OpenSSL only offers the
	#   limited-compat path) - unvalidated; separate tested change.
	# - LUA: lua54 exists, but a new runtime dep on the hot path of a
	#   security release is the wrong vehicle; separate decision.
	# - SYSTEMD: Type=simple unit never uses sd_notify; the flag alone
	#   is dead code - needs Type=notify plus testing as one change.
	# - LIBCRYPT: musl ships DES-only crypt (no strong hashes); the
	#   userlist crypt-password it enables would be weak by
	#   construction. CRYPT_H unneeded (musl needs no include guard).
	# - LINUX_CAP: inert unless the service drops root, which needs
	#   service-identity design first - not a bare flag flip.
	# - ENGINE: OpenSSL engines are deprecated with no Saphira
	#   consumers; ECH: stock OpenSSL does not implement it.
	# - OT/device-detection (opentelemetry/Atlas/51Degrees/WURFL):
	#   third-party libs absent from the tree - BLOCKED_BY_<lib>.
	# - STATIC_PCRE2: static linking contradicts the dynamic policy;
	#   MEMORY_PROFILING: glibc-only, N/A on musl.
	make -j${JOBS:-$(nproc)} \
		TARGET=linux-musl \
		USE_GETADDRINFO=1 \
		USE_KTLS=1 \
		USE_NS=1 \
		USE_OPENSSL=1 \
		USE_PCRE2=1 \
		USE_PCRE2_JIT=1 \
		USE_PROMEX=1 \
		USE_SHM_OPEN=1 \
		USE_TFO=1 \
		USE_ZLIB=1

	# Identity proof: the built binary must name HAProxy. NOTE: plain
	# grep -c (never -q): under the worker's pipefail, grep -q quits
	# at the first match and haproxy dies of SIGPIPE mid-banner
	# (proven: 3.4.7-r1 failed rc=141 at this exact line).
	[ "$(./haproxy -vv | grep -ci '^HAProxy')" -gt 0 ] || {
		echo "ERROR: built haproxy does not identify itself" >&2
		return 1
	}
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

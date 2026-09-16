#!/bin/sh

# haproxy-geoip: GeoIP country-map tooling for HAProxy.
#
# Packages the iprange/ip6range range-to-CIDR converters from the
# HAProxy source tree (admin/iprange, same 3.4.3 tarball the
# haproxy package builds) plus a map-builder script and a config
# example. Flow: MaxMind GeoLite2-Country CSVs (fetched at runtime
# via geoipupdate - license-keyed and weekly, never vendored)
# become HAProxy map_ip() tables for country allow/deny rules.
#
# Version tracks the HAProxy source the tools come from; the
# tarball is referenced from the haproxy recipe's files/ by exact
# basename, so a haproxy source upgrade breaks this build loudly
# until the pairing is re-validated (same coupling contract as
# nginx-mod-modsecurity).

pkgname=haproxy-geoip
pkgver=3.4.3
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="HAProxy GeoIP country-map tools (iprange plus map builder)"
license=GPL-2.0-or-later
origin=haproxy-geoip
repo=saphira
url=https://www.haproxy.org/

depends="
    musl
"
makedepends="
    binutils
    gcc
    make
"

recipe_build()
{
	# Exact haproxy source coupling (see header).
	haproxy_src="$RECIPE_DIR/../haproxy/files/haproxy-3.4.3.tar.gz"
	haproxy_sha256=7fa666d36d198275999e2a68dda44d3d37960f2f7aed3a595fb811f4fd0515b5
	echo "$haproxy_sha256  $haproxy_src" | sha256sum -c -
	tar --no-same-owner -C "$SRC" -xf "$haproxy_src" haproxy-3.4.3/admin/iprange
	cd "$SRC/haproxy-3.4.3/admin/iprange"
	# Upstream Makefile forces -s (strip); keep symbols for parity
	# with every other Saphira binary.
	cc -O2 -pipe -o iprange iprange.c
	cc -O2 -pipe -o ip6range ip6range.c
	./iprange < /dev/null
	./ip6range < /dev/null
}

recipe_install()
{
	install -D -m 0755 "$SRC/haproxy-3.4.3/admin/iprange/iprange" \
		"$PKGDEST/usr/bin/iprange"
	install -D -m 0755 "$SRC/haproxy-3.4.3/admin/iprange/ip6range" \
		"$PKGDEST/usr/bin/ip6range"
	install -D -m 0755 "$RECIPE_DIR/files/haproxy-geoip-build-maps" \
		"$PKGDEST/usr/bin/haproxy-geoip-build-maps"
	install -D -m 0644 "$RECIPE_DIR/files/geoip.cfg.example" \
		"$PKGDEST/usr/share/doc/haproxy-geoip/geoip.cfg.example"
}

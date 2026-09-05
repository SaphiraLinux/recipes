#!/bin/sh

pkgname=geomyidae
pkgver=0.99
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Geomyidae: small C-based RFC 1436 Gopher server'
license='MIT'
origin=geomyidae
repo=saphira
url=https://r-36.net/scm/geomyidae/
source=ftp://bitreich.org/releases/geomyidae/geomyidae-v${pkgver}.tar.gz
sha256=427014aafca2f9bd789088ea9eb798e9a74597ada09518ae5fd42255a991eb3c

# RFC 1436 Gopher server; links libtls (libretls) for Gopher-over-TLS.
depends="libretls"

makedepends="
	gcc
	make
	libretls-dev
"

# TLS is built in via libretls (the libtls API implemented on OpenSSL,
# ported as the native libretls package).  Upstream defaults enable TLS
# (-DENABLE_TLS / -ltls); the switches are passed explicitly here per
# feature policy.  Runtime opt-in stays with the operator: -t keyfile
# certfile on the command line / service options.
# CC override: the upstream Makefile is .POSIX with no CC definition, so
# GNU make defaults to the POSIX `c99` driver, which the sandbox does not
# ship (gcc-dev provides cc -> gcc).  Overriding at build time keeps the
# upstream source pristine and records the Saphira build choice in the
# recipe where it belongs.
recipe_build()
{
	make -C "$SRC" \
		PREFIX=/usr \
		CC="${CC:-cc}" \
		TLS_CFLAGS=-DENABLE_TLS \
		TLS_LDFLAGS=-ltls \
		-j${JOBS:-$(nproc)}
}

recipe_install()
{
	# Plain manual install: upstream Makefile's install target assumes
	# host prefixes; DESTDIR semantics are not guaranteed upstream.
	install -Dm0755 "$SRC/geomyidae" "$PKGDEST/usr/bin/geomyidae"
	install -Dm0644 "$SRC/geomyidae.8" "$PKGDEST/usr/share/man/man8/geomyidae.8"

	# Saphira default content root (upstream default /var/gopher is
	# deliberately overridden): the daemon serves /srv/gopher.  The
	# directory ships empty; live content is seeded at first service
	# start by the helper below and never overwritten afterwards.
	install -d -m 0755 "$PKGDEST/srv/gopher"

	# Package-owned templates/reference content.  Operators edit the
	# live copies under /srv/gopher, never these.
	install -d -m 0755 "$PKGDEST/usr/share/geomyidae/default"
	install -m 0644 "$RECIPE_DIR/files/default/gophermap" \
		"$PKGDEST/usr/share/geomyidae/default/gophermap"
	install -m 0644 "$RECIPE_DIR/files/default/about.txt" \
		"$PKGDEST/usr/share/geomyidae/default/about.txt"
	install -m 0644 "$RECIPE_DIR/files/default/README" \
		"$PKGDEST/usr/share/geomyidae/default/README"

	# Shared seeding helper used by BOTH init implementations (creates
	# the service account only if saphira-baselayout has not provided
	# it; seeds /srv/gopher only where operator content is absent).
	install -d -m 0755 "$PKGDEST/usr/libexec/saphira"
	install -m 0755 "$RECIPE_DIR/files/seed-defaults.sh" \
		"$PKGDEST/usr/libexec/saphira/geomyidae-seed-defaults"

	# Dual-init policy: both formats ship unconditionally, neither is
	# enabled automatically.
	install -Dm0755 "$RECIPE_DIR/files/geomyidae.initd" \
		"$PKGDEST/etc/init.d/geomyidae"
	install -Dm0644 "$RECIPE_DIR/files/geomyidae.service" \
		"$PKGDEST/usr/lib/systemd/system/geomyidae.service"
}

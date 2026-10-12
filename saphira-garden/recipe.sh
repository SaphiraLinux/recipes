#!/bin/sh

pkgname=saphira-garden
pkgver=0.1.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Saphira Garden network access controller and walled garden (TUN datapath, RADIUS, captive portal)"
license="BUSL-1.1"
origin=saphira-garden
repo=saphira
url=https://github.com/akadatalimited/saphira-garden
disabled=yes
disabled_reason='build breaks on source-tree layout (recipe expects source/saphira-garden, extraction does not produce it); WIP recipe, kept for lab work, not autobuilt'
source=saphira-garden-0.1.0.tar
sha256=6ac97a361675432126ad9f9d618fc7476335b79999d433fb8399f5464a754043

depends="
    openssl
"

makedepends="
    binutils
    gcc
    make
    musl-dev
    openssl-dev
"

# Plain make, no autotools and no cmake: the build system generates no
# source. musl-only by construction -- nothing here is glibc specific, and
# the only external dependency is OpenSSL 3 through EVP. We use MD5 and
# HMAC-MD5 because RFC 2865 and RFC 3579 mandate them, and nothing else, so
# OpenSSL's legacy provider is never loaded (no MD4, no DES, no MSCHAPv2
# cryptography in this daemon -- FreeRADIUS performs those).
recipe_build()
{
	cd "$SRC/saphira-garden"
	make
	# Prove the configuration validator agrees with the shipped config
	# before we package it. A config this daemon rejects must not ship.
	./saphira-garden -t -c conf/garden.toml
	# The tests are hermetic and need no privileges.
	make test
}

recipe_install()
{
	install -D -m 0755 "$SRC/saphira-garden/saphira-garden" \
		"$PKGDEST/usr/sbin/saphira-garden"
	install -D -m 0644 "$SRC/saphira-garden/conf/garden.toml" \
		"$PKGDEST/etc/saphira/garden/garden.toml"
	# Dual init: ship both unconditionally, enable neither. The openrc
	# script and the systemd unit are inert unless the operator chooses.
	install -D -m 0755 "$RECIPE_DIR/files/saphira-garden.initd" \
		"$PKGDEST/etc/init.d/saphira-garden"
	install -D -m 0644 "$RECIPE_DIR/files/saphira-garden.service" \
		"$PKGDEST/usr/lib/systemd/system/saphira-garden.service"
	# Runtime identity: saphira-garden. The daemon starts as root only long
	# enough to create the TUN and open its access-side AF_PACKET socket,
	# then drops to this account permanently and runs with no capabilities.
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/saphira-garden" \
		"$PKGDEST/usr/share/saphira/accounts.d/saphira-garden"
	install -D -m 0700 "$RECIPE_DIR/files/radius.secret" \
		"$PKGDEST/etc/saphira/garden/radius.secret"
	install -D -m 0700 "$RECIPE_DIR/files/portal.secret" \
		"$PKGDEST/etc/saphira/garden/portal.secret"
	install -d -m 0750 "$PKGDEST/var/lib/saphira-garden" \
		"$PKGDEST/run/saphira-garden"
	install -D -m 0644 "$RECIPE_DIR/files/LICENCE-summary.txt" \
		"$PKGDEST/usr/share/licenses/saphira-garden/LICENSE.txt"
	install -D -m 0644 "$RECIPE_DIR/files/PROVENANCE.md" \
		"$PKGDEST/usr/share/doc/saphira-garden/PROVENANCE.md"
}

recipe_check()
{
	# Config validation must work from an installed prefix.
	"$PKGDEST/usr/sbin/saphira-garden" -t \
		-c "$PKGDEST/etc/saphira/garden/garden.toml"
	# The secrets must not be world readable.
	[ "$(stat -c '%a' "$PKGDEST/etc/saphira/garden/radius.secret")" = 700 ] \
		|| { echo "radius.secret is not 0700" >&2; exit 1; }
	[ "$(stat -c '%a' "$PKGDEST/etc/saphira/garden/portal.secret")" = 700 ] \
		|| { echo "portal.secret is not 0700" >&2; exit 1; }
	# The literal-secret configuration key must not exist: the schema has
	# no such key, and a config carrying one must be rejected.
	grep -q '^secret[[:space:]]*=' "$PKGDEST/etc/saphira/garden/garden.toml" \
		&& { echo "shipped config contains a literal secret" >&2; exit 1; }
	return 0
}

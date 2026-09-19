#!/bin/sh

pkgname=geoipupdate
pkgver=8.0.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='MaxMind GeoIP database updater (GeoLite2/GeoIP2 .mmdb fetcher)'
license='Apache-2.0 OR MIT'
origin=geoipupdate
repo=saphira
url=https://github.com/maxmind/geoipupdate
source=https://github.com/maxmind/geoipupdate/archive/refs/tags/v8.0.0.tar.gz
sha256=5c08b39d2ac49ad492138b3d618dddac130065852b6237ec450bac856ace7e0a
# Upstream is Go (go 1.25.0 directive, no toolchain line); Saphira
# ships go 1.27.0-r1. GOTOOLCHAIN=local pins the repository
# toolchain - the build fails closed instead of downloading one.
# Module tree is NOT vendored (age/github-cli precedent): the
# release tarball is pinned and modules resolve in the worker
# (GOFLAGS=-mod=mod, GOCACHE/GOPATH under BUILDDIR). Static musl
# binary (CGO_ENABLED=0), GOAMD64=v3 per the Saphira baseline.
# Saphira crypt/data policy: the .mmdb databases are
# account-gated runtime data under /var/lib/GeoIP, never package
# payload. Only the example config ships; the operator creates
# /etc/GeoIP.conf (0600) with real AccountID/LicenseKey.
# Saphira paths are baked via upstream's own CONFFILE/DATADIR
# overrides so bare `geoipupdate -v` does the right thing.

# Man pages are NOT built in r1: upstream generates them via
# dev-bin/make-man-pages.pl which requires pandoc, and Saphira has
# no pandoc package yet (BLOCKED_BY_pandoc: port it, then re-enable
# `manpages` + the -doc split). The source .md docs ship under
# /usr/share/doc/geoipupdate instead; nothing is vendored by hand.

depends=""
makedepends="
	go
	make
"

recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/v8.0.0.tar.gz" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/v8.0.0.tar.gz"
	mkdir -p "$BUILDDIR"
	export GOCACHE="$BUILDDIR/.gocache" GOPATH="$BUILDDIR/.gopath"
	export GOFLAGS=-mod=mod CGO_ENABLED=0 GOTOOLCHAIN=local GOAMD64=v3
	cd "$SRC"
	go mod download
	# Binary + rendered GeoIP.conf only (see pandoc note above):
	# explicit make targets, not the default `all`. BUILDDIR is
	# pinned on the command line: the worker exports $BUILDDIR for
	# its own staging, and make imports the environment, which
	# would otherwise repoint upstream's relative build dir.
	make BUILDDIR=build build/geoipupdate build/GeoIP.conf \
		CONFFILE=/etc/GeoIP.conf DATADIR=/var/lib/GeoIP VERSION=8.0.0
	# Acceptance smoke before staging: exact version string.
	./build/geoipupdate -V 2>&1 | grep -q '8\.0\.0' || {
		echo "ERROR: unexpected version output" >&2
		./build/geoipupdate -V >&2
		return 1
	}
	echo "geoipupdate build OK: $(./build/geoipupdate -V 2>&1 | head -1)"
}

recipe_install()
{
	install -D -m 0755 "$SRC/build/geoipupdate" "$PKGDEST/usr/bin/geoipupdate"
	install -D -m 0644 "$SRC/build/GeoIP.conf" "$PKGDEST/etc/GeoIP.conf.example"
	install -d -m 0755 "$PKGDEST/var/lib/GeoIP"
	install -D -m 0644 "$RECIPE_DIR/files/geoipupdate.service" \
		"$PKGDEST/usr/lib/systemd/system/geoipupdate.service"
	install -D -m 0644 "$RECIPE_DIR/files/geoipupdate.timer" \
		"$PKGDEST/usr/lib/systemd/system/geoipupdate.timer"
	install -D -m 0755 "$RECIPE_DIR/files/geoipupdate.initd" \
		"$PKGDEST/etc/init.d/geoipupdate"
	install -D -m 0644 "$SRC/doc/geoipupdate.md" \
		"$PKGDEST/usr/share/doc/geoipupdate/geoipupdate.md"
	install -D -m 0644 "$SRC/doc/GeoIP.conf.md" \
		"$PKGDEST/usr/share/doc/geoipupdate/GeoIP.conf.md"
	install -D -m 0644 "$SRC/LICENSE-APACHE" \
		"$PKGDEST/usr/share/licenses/geoipupdate/LICENSE-APACHE"
	install -D -m 0644 "$SRC/LICENSE-MIT" \
		"$PKGDEST/usr/share/licenses/geoipupdate/LICENSE-MIT"
	# Policy asserts: no live credentials template promoted to a
	# real config, and no database payload baked into the package.
	test ! -e "$PKGDEST/etc/GeoIP.conf" || {
		echo "ERROR: real GeoIP.conf staged (example only)" >&2; return 1; }
	test -f "$PKGDEST/etc/GeoIP.conf.example" || {
		echo "ERROR: GeoIP.conf.example missing" >&2; return 1; }
	find "$PKGDEST" -name '*.mmdb' | grep -q . && {
		echo "ERROR: .mmdb database staged (runtime data only)" >&2; return 1; } || true
	grep -q YOUR_LICENSE_KEY_HERE "$PKGDEST/etc/GeoIP.conf.example" || {
		echo "ERROR: example config lacks credential placeholders" >&2; return 1; }
}

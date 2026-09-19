#!/bin/sh

# coraza-spoa: Coraza WAF as an HAProxy SPOE agent (Go daemon).
#
# This is the haproxy target: HAProxy has no ModSecurity connector,
# so the WAF runs as a Stream Processing Offload Agent that HAProxy
# queries per request (filter spoe + use-backend coraza-spoa). Coraza
# passes 100% of the CRS v4 suite; the agent embeds the CRS LTS line
# (go.mod: coraza-coreruleset v4.25.0 - the same family as the
# coreruleset package serving nginx), so no rule path wiring is needed.
#
# Builds with the hatched repo Go, whatever it is (GOTOOLCHAIN=local,
# house rule - toolchain pinning rots). Floor note: upstream go.mod
# demands go >=1.25.7 while the repo ships 1.24.11, so this package
# waits on the Saphira go 1.25 upgrade (go recipe: "future upgrade")
# and the builder proves it then. No toolchain downloads, ever.
# Modules otherwise follow the age precedent (GOFLAGS=-mod=mod,
# GOCACHE/GOPATH under BUILDDIR, static musl via CGO_ENABLED=0,
# GOAMD64=v3 baseline).

pkgname=coraza-spoa
pkgver=0.7.1
pkgrel=2
# r2: OpenRC-tracked pidfile /run/coraza-spoa.pid ->
# /var/run/coraza-spoa.pid; RuntimeDirectory=coraza-spoa removed
# (created an unconsumed /run/coraza-spoa dir - the stateless daemon
# uses no runtime dir). No fhs.d fragment by rule: flat tmpfs
# pidfile needs no migration (document-and-leave, haproxy
# precedent). Payload change, revision bumps.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Coraza WAF SPOA daemon for HAProxy"
license=Apache-2.0
origin=coraza-spoa
repo=saphira
url=https://coraza.io/
source=https://github.com/corazawaf/coraza-spoa/archive/refs/tags/v0.7.1.tar.gz
sha256=272838cc877759153c28f4ac0dc7166c4a9ad9169d17dfa5530fa975792619a7

depends="musl"
makedepends="go"

recipe_build()
{
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/v0.7.1.tar.gz"
	echo "$sha256  $RECIPE_DIR/files/v0.7.1.tar.gz" | sha256sum -c -
	mkdir -p "$BUILDDIR"
	export GOCACHE="$BUILDDIR/.gocache" GOPATH="$BUILDDIR/.gopath"
	export GOFLAGS=-mod=mod CGO_ENABLED=0 GOTOOLCHAIN=local GOAMD64=v3
	export HOME="$BUILDDIR"
	cd "$SRC"
	go build -trimpath \
		-ldflags="-buildid= -X main.version=$pkgver" \
		-o "$BUILDDIR/coraza-spoa" .
	"$BUILDDIR/coraza-spoa" --version | grep -q "$pkgver" ||
		{ echo "ERROR: built coraza-spoa is not $pkgver" >&2; return 1; }
}

recipe_install()
{
	install -D -m0755 "$BUILDDIR/coraza-spoa" "$PKGDEST/usr/bin/coraza-spoa"
	# Dual init (mandatory for service packages): openrc + systemd,
	# adapted from upstream contrib (Fedora-isms removed).
	install -D -m0755 "$RECIPE_DIR/files/coraza-spoa.initd" \
		"$PKGDEST/etc/init.d/coraza-spoa"
	install -D -m0644 "$RECIPE_DIR/files/coraza-spoa.service" \
		"$PKGDEST/usr/lib/systemd/system/coraza-spoa.service"
	# Default config (localhost-only, DetectionOnly) plus the upstream
	# HAProxy wiring as inert examples - haproxy itself is untouched.
	install -D -m0644 "$RECIPE_DIR/files/config.yaml" \
		"$PKGDEST/etc/coraza-spoa/config.yaml"
	install -D -m0644 "$SRC/example/haproxy/coraza.cfg" \
		"$PKGDEST/usr/share/doc/coraza-spoa/examples/haproxy-coraza.cfg"
	install -D -m0644 "$SRC/example/haproxy/haproxy.cfg" \
		"$PKGDEST/usr/share/doc/coraza-spoa/examples/haproxy.cfg"
	install -D -m0644 "$RECIPE_DIR/files/accounts.d/coraza-spoa" \
		"$PKGDEST/usr/share/saphira/accounts.d/coraza-spoa"
	install -d -m0755 "$PKGDEST/var/log/coraza-spoa"
	# The staged daemon must accept its own shipped config offline.
	"$PKGDEST/usr/bin/coraza-spoa" -config "$PKGDEST/etc/coraza-spoa/config.yaml" \
		-validate || { echo "ERROR: staged coraza-spoa rejects its config" >&2; return 1; }
}

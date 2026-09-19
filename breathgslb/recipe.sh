#!/bin/sh

pkgname=breathgslb
pkgver=0.0.1
pkgrel=3
# r3: capabilities declared (saphira-permissions V1): the
# cap_net_bind_service file capability moves from a build-time
# setcap into files/caps.d/breathgslb, converged at install/upgrade
# by the generated ensure-caps caller. Payload change, bumps.
# r2: OpenRC-tracked pidfile /run/breathgslb.pid -> /var/run/breathgslb.pid
# (flat, no subdir). No fhs.d fragment by rule: flat tmpfs pidfile
# needs no migration (document-and-leave, unbound precedent).
# Payload change, revision bumps.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="BreathGSLB health-checked authoritative DNS with global load balancing"
license=MIT
origin=breathgslb
repo=saphira
url=https://github.com/akadata/breathgslb
source=https://github.com/akadata/breathgslb/archive/eed6ce94651f2aead90e0257284ae9981bdcd9ed.tar.gz
sha256=1508a20f70bab782cc7c684c82117a6e1cf9e24c182dcb7c655ff1225ca83c21

depends="
    ca-certificates
"

# BLOCKED_BY_go-toolchain: go.mod requires go >= 1.24.5 and no Go
# recipe or binary exists anywhere in the tree or on the builders yet.
# Staged honestly so the first Go build attempt fails closed here with
# a missing makedepends instead of deep in the compile. When Go lands:
# mirror upstream release-musl (CGO_ENABLED=0, -tags netgo, static) -
# no gcc needed. Upstream ships no vendor/ directory, so the first
# build also proves module fetching in the worker (GOFLAGS -mod=mod;
# GOCACHE/GOPATH under BUILDDIR); if the worker has no module proxy,
# vendor the module tree into files/ first (go mod vendor needs the
# toolchain, so that happens after Go lands too).
# Daemon version stamping passes the pinned commit explicitly (the
# Makefile's git rev-parse cannot run on a vendor tarball).
makedepends="
    go
"

# v1 scope: daemon + license tools + man + units + identity. The admin
# web UI (src/web, separate binary + service surface) follows once the
# daemon package builds and its config/secret handling is reviewed.
# No live config shipped (upstream ships none either): the operator
# provisions /etc/breathgslb/config.yaml (see breathgslb.conf(5));
# both service scripts refuse to start without it.

recipe_build()
{
	# The builder downloads source=, verifies sha256 and extracts to
	# $SRC. Go builds out of tree (no source mutation): module work
	# goes to GOCACHE/GOPATH under BUILDDIR.
	mkdir -p "$BUILDDIR"
	export GOCACHE="$BUILDDIR/.gocache" GOPATH="$BUILDDIR/.gopath"
	export GOFLAGS=-mod=mod CGO_ENABLED=0
	LDFLAGS="-s -w -X 'main.version=0.0.1.eed6ce9' -X 'main.buildOS=linux'"
	go -C "$SRC/src" build -tags netgo -trimpath -ldflags "$LDFLAGS -extldflags '-static'" \
		-o "$BUILDDIR/breathgslb" .
	go -C "$SRC/src" build -tags tools -trimpath -ldflags "$LDFLAGS" \
		-o "$BUILDDIR/licensectl" ./cmd/licensectl
	go -C "$SRC/src" build -tags tools -trimpath -ldflags "$LDFLAGS" \
		-o "$BUILDDIR/licensegen" ./cmd/licensegen
}

recipe_install()
{
	install -D -m 0755 "$BUILDDIR/breathgslb" "$PKGDEST/usr/sbin/breathgslb"
	install -D -m 0755 "$BUILDDIR/licensectl" "$PKGDEST/usr/bin/breathgslb-licensectl"
	install -D -m 0755 "$BUILDDIR/licensegen" "$PKGDEST/usr/bin/breathgslb-licensegen"
	# Privileged port 53 as an unprivileged service (net-snmp pattern):
	# the file capability is declared in files/caps.d/breathgslb and
	# converged at install/upgrade by the generated ensure-caps
	# caller (saphira-permissions V1) — no build-time setcap.
	# (systemd additionally grants it ambiently via the unit.)
	install -D -m 0644 "$RECIPE_DIR/files/caps.d/breathgslb" \
		"$PKGDEST/usr/share/saphira/caps.d/breathgslb"
	install -D -m 0644 "$SRC/man/breathgslb.8" \
		"$PKGDEST/usr/share/man/man8/breathgslb.8"
	install -D -m 0644 "$SRC/man/breathgslb.conf.5" \
		"$PKGDEST/usr/share/man/man5/breathgslb.conf.5"
	ln -s breathgslb.conf.5 "$PKGDEST/usr/share/man/man5/breathgslb.5"
	install -D -m 0644 "$RECIPE_DIR/files/breathgslb-licensectl.8" \
		"$PKGDEST/usr/share/man/man8/breathgslb-licensectl.8"
	install -D -m 0644 "$RECIPE_DIR/files/breathgslb-licensegen.8" \
		"$PKGDEST/usr/share/man/man8/breathgslb-licensegen.8"
	install -d -m 0750 "$PKGDEST/etc/breathgslb" \
		"$PKGDEST/etc/breathgslb/keys" "$PKGDEST/etc/breathgslb/zones" \
		"$PKGDEST/etc/breathgslb/reverse" \
		"$PKGDEST/var/lib/breathgslb" "$PKGDEST/var/log/breathgslb"
	install -D -m 0755 "$RECIPE_DIR/files/breathgslb.initd" \
		"$PKGDEST/etc/init.d/breathgslb"
	install -D -m 0644 "$RECIPE_DIR/files/breathgslb.service" \
		"$PKGDEST/usr/lib/systemd/system/breathgslb.service"
	# Runtime identity declaration: breathgslb:126. makepkg generates
	# the install scripts from this fragment; the package creates its
	# identity at install time.
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/breathgslb" \
		"$PKGDEST/usr/share/saphira/accounts.d/breathgslb"
}

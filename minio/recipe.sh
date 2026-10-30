#!/bin/sh

pkgname=minio
# Upstream RELEASE.2025-10-15T17-29-55Z mapped to dotted datetime
# (monotonic with upstream time order; mapping noted here, not hidden).
pkgver=2025.10.15.17.29.55
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='MinIO S3-compatible object storage server (isolated test instances)'
license='AGPL-3.0-only'
origin=minio
repo=saphira
url=https://min.io
source=https://github.com/minio/minio/archive/refs/tags/RELEASE.2025-10-15T17-29-55Z.tar.gz
sha256=be6d0bd3696c3a13a35f02d3a0280b64319c67918b4501c5c3d87f96d000085c
# r1: initial native port. Purpose-built as the isolated S3 target for
# saphira-bucket M4 integration testing: never production storage.
# go.mod declares go 1.24.0 / toolchain go1.24.8; Saphira go is 1.27.0
# and GOTOOLCHAIN=local pins the build to the repository toolchain,
# failing closed if the language level ever exceeds it.
# Modules are NOT vendored upstream (github-cli age precedent applies):
# the release tarball is pinned and modules resolve in the worker
# (GOFLAGS=-mod=mod, GOCACHE/GOPATH/GOBIN under BUILDDIR). No CGO
# anywhere in first-party code (verified by inspection), so
# CGO_ENABLED=0 yields a static musl binary; GOAMD64=v3 per baseline.
# The admin console UI ships as the github.com/minio/console Go module
# (prebuilt embedded assets) - no node/npm anywhere in the build.
# Version stamping mirrors upstream buildscripts/gen-ldflags.go minus
# the GOPATH/GOROOT paths (build paths, not product facts); CommitID
# is the tag's commit 9e49d5e7a648f00e26f2246f4dc28e6b07f8c84a.
# Build tags are upstream's own (-tags kqueue), nothing added/removed.
# No default credentials, by design: the units refuse to start without
# MINIO_ROOT_USER/MINIO_ROOT_PASSWORD set in /etc/conf.d/minio (which
# is deliberately NOT shipped, so upgrades never touch operator
# secrets; see files/minio.confd.example). Telemetry (callhome)
# defaults OFF in the shipped units: isolated instances must not phone
# home; the operator enables it explicitly. Ports 9000 (S3) + 9001
# (console). Logs go to stdout only, so no logrotate fragment.

depends=""
makedepends="go"

recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/RELEASE.2025-10-15T17-29-55Z.tar.gz" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/RELEASE.2025-10-15T17-29-55Z.tar.gz"
	mkdir -p "$BUILDDIR"
	export GOCACHE="$BUILDDIR/.gocache" GOPATH="$BUILDDIR/.gopath" GOBIN="$BUILDDIR/.gobin"
	export GOFLAGS=-mod=mod CGO_ENABLED=0 GOTOOLCHAIN=local GOAMD64=v3
	cd "$SRC"
	# Populate the module cache first (go.mod/go.sum are complete).
	go mod download
	go build -trimpath -tags kqueue \
		-ldflags="-buildid= -s -w \
			-X github.com/minio/minio/cmd.Version=2025-10-15T17:29:55Z \
			-X github.com/minio/minio/cmd.CopyrightYear=2025 \
			-X github.com/minio/minio/cmd.ReleaseTag=RELEASE.2025-10-15T17-29-55Z \
			-X github.com/minio/minio/cmd.CommitID=9e49d5e7a648f00e26f2246f4dc28e6b07f8c84a \
			-X github.com/minio/minio/cmd.ShortCommitID=9e49d5e7a648" \
		-o "$BUILDDIR/minio" .
	# Acceptance before staging: exact release tag in version output.
	"$BUILDDIR/minio" --version | grep -q "RELEASE.2025-10-15T17-29-55Z" || {
		echo "ERROR: minio version proof failed" >&2
		"$BUILDDIR/minio" --version >&2
		return 1
	}
	echo "minio build OK: $("$BUILDDIR/minio" --version | head -1)"
}

recipe_install()
{
	install -D -m 0755 "$BUILDDIR/minio" "$PKGDEST/usr/sbin/minio"
	install -D -m 0755 "$RECIPE_DIR/files/minio.initd" \
		"$PKGDEST/etc/init.d/minio"
	install -D -m 0644 "$RECIPE_DIR/files/minio.service" \
		"$PKGDEST/usr/lib/systemd/system/minio.service"
	install -D -m 0644 "$RECIPE_DIR/files/minio.confd.example" \
		"$PKGDEST/usr/share/doc/minio/minio.confd.example"
	install -D -m 0644 "$SRC/LICENSE" \
		"$PKGDEST/usr/share/licenses/minio/LICENSE"
	# Runtime identity declaration: minio:118 required by the shipped
	# service units (minio.service User=minio, minio.initd command_user
	# minio:minio) and owner of the default data directory. makepkg
	# generates the install scripts from this fragment; the package
	# creates its identity at install time.
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/minio" \
		"$PKGDEST/usr/share/saphira/accounts.d/minio"
}

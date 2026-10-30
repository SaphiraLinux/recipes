#!/bin/sh
# Saphira recipe: saphira-bucket
#
# MinIO/S3 bucket and credential administration CLI (native C11, no
# runtime beyond libc and the libraries below). Single self-contained
# binary; no daemon, so no init units, no service identity, no
# logrotate fragment, no maintainer hooks.

pkgname=saphira-bucket
pkgver=0.1.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='MinIO/S3 bucket and credential administration CLI'
# Our own product, so our licence (BUSL-1.1, saphira-base pattern).
license='BUSL-1.1'
origin=saphira-bucket
repo=saphira
url=https://github.com/SaphiraLinux/saphira-bucket

# Upstream is a PRIVATE GitHub repo and the builder sandbox carries no
# GitHub credentials (Egg authenticates via `gh auth git-credential`,
# which does not exist inside the namespace), so a live clone fails
# with "could not read Username". Like saphira-unified-memory-mcp, this
# build vendors a byte-pinned `git archive` snapshot of the pinned
# revision (never a moving branch: the same pkgver must always mean the
# same source). Move the pin to a release tag once one is cut. With no
# source URL the worker stages the recipe dir itself into $SRC.
saphira_bucket_rev=7b120757888af7f1e9433fdc024261063dabfcbc
saphira_bucket_sha256=5789df85f56c8f1eae11cc244021990d37d25192c3510407f8ce6d3a448969f6

# Runtime libraries, listed exactly as consumed (ldd of the product
# binary): libcurl, libexpat, libargon2, libjson-c, libssl/libcrypto.
# -lrt/-ldl resolve to libc on musl and need no package.
depends="
    curl
    expat
    json-c
    libargon2
    openssl
"

makedepends="
    binutils
    gcc
    make
    musl-dev
    pkgconf
    curl-dev
    expat-dev
    json-c-dev
    libargon2-dev
    openssl-dev
"

recipe_build()
{
	# Vendored contract: verify byte identity first, then extract.
	echo "$saphira_bucket_sha256  $SRC/files/saphira-bucket-0.1.0.tar.gz" | sha256sum -c -
	mkdir -p "$SRC/pkg"
	tar --no-same-owner -C "$SRC/pkg" --strip-components=1 \
		-xzf "$SRC/files/saphira-bucket-0.1.0.tar.gz"
	# The pin decides what gets built: the tarball is the `git archive`
	# of $saphira_bucket_rev, so the hash check above is the provenance
	# gate and an installed copy traces back to exact source.
	cd "$SRC/pkg"
	# Upstream-style build honouring the builder flags; the product
	# Makefile keeps -std=c11 -Wall -Wextra -Werror always on.
	make BUILD_DIR="$BUILDDIR/sb-build" PREFIX=/usr \
		CFLAGS="${CFLAGS-}" LDFLAGS="${LDFLAGS-}"
	# The product's own unit suites are the build gate: a red suite
	# fails the package here, not in production.
	make BUILD_DIR="$BUILDDIR/sb-build" test
}

recipe_install()
{
	cd "$SRC/pkg"
	make BUILD_DIR="$BUILDDIR/sb-build" DESTDIR="$PKGDEST" \
		PREFIX=/usr install
}

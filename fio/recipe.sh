#!/bin/sh

pkgname=fio
pkgver=3.43
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Flexible I/O tester (storage benchmarking)'
license='GPL-2.0-or-later'
origin=fio
repo=saphira
url=https://github.com/axboe/fio
source=https://github.com/axboe/fio/archive/refs/tags/fio-${pkgver}.tar.gz
sha256=efa49b3f36eda9adf29294f27a87d7e457747d676cd0f73996d6365357832cfe
# r1: initial native port (CLI only; gfio is opt-in upstream and stays
# off: no GTK under the headless policy).
# Upstream publishes checksums for release BINARIES only, never for the
# GitHub auto-generated source tarball: the hash above is trust-on-first-
# use, recorded 2026-10-22, and the vendored bytes in files/ are the
# source of truth afterwards. Re-verify out-of-band on every bump.
# Explicit --disable-rdma/--disable-rbd (neither exists in the universe;
# autodetect would silently do the same, but explicit beats silent).
# libaio engine kept: it is the standard async engine for the ZFS
# benchmarks this was packaged for.

depends="libaio zlib"
makedepends="gcc libaio-dev make pkgconf zlib-dev"

recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/fio-$pkgver.tar.gz" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/fio-$pkgver.tar.gz"
	cd "$SRC"
	# layout-exception: custom configure dialect rejects unknown
	# GNU dir flags; install paths are already explicit below.
	./configure --prefix=/usr --disable-rdma --disable-rbd
	make -j"$(nproc)"
	# Proof: version renders, and the libaio engine (the ZFS-test
	# engine) is actually built in, not silently dropped.
	./fio --version | grep -q "$pkgver" ||
		{ echo "ERROR: fio version proof failed" >&2; return 1; }
	./fio --enghelp 2>/dev/null | grep -q libaio ||
		{ echo "ERROR: fio libaio engine missing" >&2; return 1; }
	# Smoke: a null-engine job runs end to end with no disk.
	./fio --name=smoke --ioengine=null --size=1M --runtime=1 --time_based >/dev/null ||
		{ echo "ERROR: fio smoke job failed" >&2; return 1; }
}

recipe_install()
{
	cd "$SRC"
	make DESTDIR="$PKGDEST" install
}

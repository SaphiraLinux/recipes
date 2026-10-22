#!/bin/sh

pkgname=btrfs-progs
pkgver=7.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Btrfs filesystem utilities (mkfs, check, rescue, balance)'
license='GPL-2.0-or-later'
origin=btrfs-progs
repo=saphira
url=https://btrfs.readthedocs.io/
source=https://www.kernel.org/pub/linux/kernel/people/kdave/btrfs-progs/btrfs-progs-v${pkgver}.tar.xz
sha256=d1f55cc2971398c9142eaa79d203e63d586a3b4b867f956664a1d68322cd4e34
# r1: initial native port. Userspace half of btrfs root support (the
# kernel half is BTRFS_FS=y on every line): mkfs.btrfs, btrfs check,
# rescue and balance/scrub tooling.
# Upstream publishes gpg signatures, no sha256 sums: the hash above is
# trust-on-first-use, recorded 2026-10-22, and the vendored bytes in
# files/ are the source of truth afterwards. Re-verify out-of-band on
# every bump.
# Every --disable-* carries its reason (feature policy):
#   --disable-documentation: sphinx is not in the universe; ship no docs.
#   --disable-python: bindings unused by anything we ship.
#   --disable-convert: needs reiserfscore (absent); ext4->btrfs
#     conversion is not a supported path, and convert drags ext2fs
#     into the runtime closure for one unused binary.
#   --disable-backtrace: musl has no execinfo/backtrace(); crash
#     traces are a glibc facility, not a filesystem requirement.
# Crypto stays at the default (builtin implementations): rescue
# environments must not depend on libgcrypt/libsodium/openssl.
# Tarball ships configure.ac without generated configure: autoreconf
# in the worker (autoconf/automake/libtool below).

depends="lzo udev util-linux zlib zstd"
makedepends="autoconf automake e2fsprogs-dev gawk gcc lzo-dev libtool make pkgconf saphira-linux-uapi-headers udev-dev util-linux-dev zlib-dev zstd-dev"

recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/btrfs-progs-v$pkgver.tar.xz" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/btrfs-progs-v$pkgver.tar.xz"
	mkdir -p "$BUILDDIR"
	cd "$SRC"
	autoreconf -fi
	./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var \
		--disable-documentation --disable-python --disable-convert \
		--disable-backtrace
	make -j"$(nproc)"
	# Proof: the built binary identifies itself (no device touched).
	./btrfs --version | grep -q "v$pkgver" ||
		{ echo "ERROR: btrfs version proof failed" >&2; return 1; }
}

recipe_install()
{
	cd "$SRC"
	make DESTDIR="$PKGDEST" install
}

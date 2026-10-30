#!/bin/sh

pkgname=binutils
pkgver=2.46.1
pkgrel=4
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='GNU binary utilities (as, ld, ar, nm, objcopy, readelf) - Genesis 16.2 toolchain'
# Architecture plumbing. pkgarch comes from SAPHIRA_ARCH, so everything the
# build is told to target is derived from that SAME value: a package can no
# longer be built for one architecture and labelled as another. An
# unrecognised architecture fails closed rather than defaulting, because a
# silent default is exactly how a mislabelled package reaches a signed
# repository.
case "$pkgarch" in
x86_64)
	ARCH_TRIPLET=x86_64-akadata-linux-musl
	;;
aarch64)
	ARCH_TRIPLET=aarch64-akadata-linux-musl
	;;
riscv64)
	ARCH_TRIPLET=riscv64-akadata-linux-musl
	;;
*)
	echo "ERROR: unsupported SAPHIRA_ARCH '$pkgarch' for binutils" >&2
	return 1
	;;
esac
license='GPL-3.0-or-later'
origin=binutils
repo=saphira
url=https://www.gnu.org/software/binutils/
# Vendored: https://ftp.gnu.org/gnu/binutils/binutils-2.46.1.tar.xz
binutils_sha256=e127a709cba24c76de8936cb7083dd768f28cd37eb010492e2f19b71eb1294e4

depends="zlib"
makedepends="
	binutils
	gawk
	gcc
	make
	pkgconf
	zlib-dev
	zstd-dev
"

subpackages="$pkgname-dev"

recipe_build()
{
	BUBALL="$RECIPE_DIR/files/binutils-2.46.1.tar.xz"
	echo "$binutils_sha256  $BUBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$BUBALL"
	mkdir -p "$BUILDDIR"
	cd "$BUILDDIR"
	../source/configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--with-sysroot=/ \
		--build="$ARCH_TRIPLET" \
		--host="$ARCH_TRIPLET" \
		--target="$ARCH_TRIPLET" \
		--enable-ld=default \
		--enable-plugins \
		--enable-64-bit-bfd \
		--enable-default-pie \
		--with-system-zlib \
		--disable-multilib \
		--disable-nls \
		--disable-werror \
		--disable-gdb \
		--with-pkgversion='Saphira 2.46.1'
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
	rm -f "$PKGDEST"/usr/lib/*.la
}

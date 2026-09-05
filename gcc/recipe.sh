#!/bin/sh

pkgname=gcc
pkgver=16.2.0
pkgrel=8
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='GNU Compiler Collection 16.2.0 (C, C++, Fortran, ObjC/ObjC++, Modula-2, LTO; AKADATA branch-cost policy)'
license='GPL-3.0-or-later WITH GCC Runtime Library Exception'
origin=gcc
repo=saphira
url=https://gcc.gnu.org/
# Vendored: https://ftp.gnu.org/gnu/gcc/gcc-16.1.0/gcc-16.1.0.tar.xz
gcc_sha256=e6738e29597f733270731aa90600f37ffdc045079dfc27ec7e8192cc81085c3e

# GENESIS compiler (operator decision 2026-08-30): 16.2.0 with 102+
# upstream bug fixes over 16.1. Lineage: 16.1.0-r2 builds 16.2.0-r0
# (prove every frontend), then 16.2.0 rebuilds itself -> Genesis.
# Same major release: libstdc++.so.6 / libgcc_s.so.1 ABI family
# unchanged - existing packages keep running.
#
# Self-hosting language set: c,c++,fortran,objc,obj-c++,m2,lto. COBOL
# excluded: libgcobol requires glibc execinfo.h (backtrace), absent on
# musl. Ada/D/Go/Rust need bootstrap front ends (gnat1/gdc1/gccgo1/
# rust1); future Ada path: AdaCore gnat-llvm. Do NOT fall back to an
# Alpine or other-distro bootstrap toolchain (AGENTS.md policy).
#
# Patch evidence on pristine 16.2.0: branch-cost fix NOT upstream
# (still COSTS_N_INSNS (2),) -> 0001 carried; t-linux64 still
# m64=../lib64 -> 0002 carried. Both verified applying cleanly.
#
# Saphira compiler policy: 0001 preserves the AKADATA backport of GCC
# commit 52cd02606b906160bf47001a00b446c35d46f15f (x86 generic tune
# branch misprediction cost COSTS_N_INSNS (2) -> (2) + 3) - verified
# against this source; do not silently drop it on upgrades.
depends="gcc-libs gmp mpfr mpc isl zlib zstd binutils"
# gcc-dev kept until the live toolchain is r8+: r8 is the first revision
# with headers in main, so building it still needs the r7 -dev headers
# installed. Drop that line once r8+ is live.
makedepends="
	bison
	binutils
	flex
	gawk
	gcc
	gcc-dev
	gcc-libs
	gmp-dev
	isl-dev
	m4
	make
	mpc-dev
	mpfr-dev
	perl
	python3
	zlib-dev
	zstd
	zstd-dev
"

subpackages="$pkgname-doc $pkgname-libs"

# A compiler is self-contained (operator decision 2026-09-05): there is
# no gcc-dev split. Headers, static libs and dev links all ship in main
# gcc; only -doc and runtime -libs split out. replaces= absorbs the
# retired gcc-dev so upgrades take its files without conflicts.
# Build convention (see RECIPE_RULES): C and C++ builds alike declare
# makedepends gcc. Runtime-only systems keep gcc-libs without a compiler.
replaces="gcc-dev"

recipe_build()
{
	GCCBALL="$RECIPE_DIR/files/gcc-16.2.0.tar.xz"
	echo "$gcc_sha256  $GCCBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$GCCBALL"
	patch -d "$SRC" -Np1 \
		-i "$RECIPE_DIR/files/0001-x86-increase-generic-tune-branch-misprediction-cost.patch"
	patch -d "$SRC" -Np1 \
		-i "$RECIPE_DIR/files/0002-m64-multilib-osdir-lib-not-lib64.patch"
	mkdir -p "$BUILDDIR"
	cd "$BUILDDIR"
	# Same-version --disable-bootstrap build: our published gcc 16.1.0
	# compiles this tree directly (no 3-stage dance, no foreign toolchain).
	../source/configure \
		--build=x86_64-akadata-linux-musl \
		--host=x86_64-akadata-linux-musl \
		--target=x86_64-akadata-linux-musl \
		--prefix=/usr \
		--with-sysroot=/ \
		--with-toolexeclibdir=/usr/lib \
		--with-native-system-header-dir=/usr/include \
		--with-arch=x86-64-v3 \
		--with-tune=generic \
		--with-gmp=/usr \
		--with-mpfr=/usr \
		--with-mpc=/usr \
		--with-isl=/usr \
		--with-system-zlib \
		--with-pkgversion='Saphira 16.2.0 (akadata-branch-cost, lib-only layout)' \
		--enable-languages=c,c++,fortran,objc,obj-c++,m2,lto \
		--enable-threads=posix \
		--enable-shared \
		--enable-libatomic \
		--enable-libgomp \
		--enable-libquadmath \
		--disable-bootstrap \
		--disable-multilib \
		--disable-nls \
		--disable-analyzer \
		--disable-libsanitizer \
		--disable-libssp \
		--disable-libvtv \
		--disable-libitm \
		--disable-werror \
		--disable-fixincludes
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
	# cc is not installed by upstream GCC `make install`; every distro adds
	# it in packaging. Build systems (Meson sanity checks pair `ccache cc`)
	# and ccache via CCACHE_PATH expect a real /usr/bin/cc.
	ln -s gcc "$PKGDEST/usr/bin/cc"
	# The primary multilib dir resolves to ../lib64 (/usr/lib/../lib64)
	# even under --disable-multilib. Saphira forbids /lib64 and
	# /usr/lib64: single-multilib payloads merge into /usr/lib.
	for d in usr/lib64 lib64; do
		if [ -d "$PKGDEST/$d" ]; then
			cp -a "$PKGDEST/$d/." "$PKGDEST/usr/lib/"
			rm -rf "$PKGDEST/$d"
		fi
	done
	rm -f "$PKGDEST"/usr/lib/*.la
}

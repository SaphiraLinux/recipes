#!/bin/sh

pkgname=gcc
pkgver=${SAPHIRA_GCC_VERSION:-16.2.0}
pkgrel=10
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="GNU Compiler Collection ${pkgver} (C, C++, Fortran, ObjC/ObjC++, Modula-2, LTO; AKADATA branch-cost policy)"
# Architecture plumbing. pkgarch comes from SAPHIRA_ARCH, so everything the
# build is told to target is derived from that SAME value: a package can no
# longer be built for one architecture and labelled as another. An
# unrecognised architecture fails closed rather than defaulting, because a
# silent default is exactly how a mislabelled package reaches a signed
# repository.
case "$pkgarch" in
x86_64)
	ARCH_TRIPLET=x86_64-akadata-linux-musl
	GCC_ARCH=x86-64-v3
	;;
aarch64)
	ARCH_TRIPLET=aarch64-akadata-linux-musl
	GCC_ARCH=armv8-a
	;;
riscv64)
	ARCH_TRIPLET=riscv64-akadata-linux-musl
	GCC_ARCH=rv64gc
	;;
*)
	echo "ERROR: unsupported SAPHIRA_ARCH '$pkgarch' for gcc" >&2
	return 1
	;;
esac

# Branded so --version states whether the AKADATA branch-cost policy is in
# force for THIS build, rather than claiming it unconditionally. The
# backport edits gcc/config/i386, which no other backend compiles, and
# its "+3" would be hardware-wrong on aarch64 (shallower pipelines,
# lower documented mispredict cost): x86-only, explicitly not applicable
# elsewhere. Recorded as an explicit reviewed N/A, never a silent drop.
case "$pkgarch" in
x86_64) BRANCH_COST_NOTE=akadata-branch-cost ;;
*)      BRANCH_COST_NOTE=no-branch-cost-x86-policy-N-A ;;
esac
license='GPL-3.0-or-later WITH GCC Runtime Library Exception'
origin=gcc
repo=saphira
url=https://gcc.gnu.org/
# Upstream tarball per version line (SAPHIRA_GCC_VERSION selects; kernel
# recipe pattern). vendor=+sha256= is the fetch contract: when the archive
# is absent from files/, the builder downloads vendor=, verifies sha256,
# and exposes the verified archive as $SOURCE_ARCHIVE. A present local
# archive always wins and is never re-downloaded.
case "$pkgver" in
	16.1.0)
		vendor=https://ftp.gnu.org/gnu/gcc/gcc-16.1.0/gcc-16.1.0.tar.xz
		sha256=50efb4d94c3397aff3b0d61a5abd748b4dd31d9d3f2ab7be05b171d36a510f79
		;;
	16.2.0)
		vendor=https://ftp.gnu.org/gnu/gcc/gcc-16.2.0/gcc-16.2.0.tar.xz
		sha256=e6738e29597f733270731aa90600f37ffdc045079dfc27ec7e8192cc81085c3e
		;;
	*) echo "ERROR: no pinned vendor/sha256 for gcc $pkgver" >&2; return 1 ;;
esac

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
# gcc-dev is NOT a makedepends entry. r8 is the first revision with headers
# in main, so the r8 bootstrap in makedepends already provides them; and r8
# declares replaces="gcc-dev", so apk refuses to install the pair at all:
#
#   ERROR: unable to select packages:
#     gcc-16.2.0-r8:
#       breaks: gcc-dev-16.2.0-r7[gcc=16.2.0-r7]
#
# That is not a closure to trim, it is a build that cannot start.
makedepends="
	bison
	binutils
	flex
	gawk
	gcc
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
	# Local archive wins when present (verified, never re-downloaded);
	# otherwise build from the builder-verified $SOURCE_ARCHIVE.
	GCCBALL="$RECIPE_DIR/files/gcc-${pkgver}.tar.xz"
	if [ -f "$GCCBALL" ]; then
		echo "$sha256  $GCCBALL" | sha256sum -c -
	else
		[ -n "${SOURCE_ARCHIVE-}" ] && [ -f "$SOURCE_ARCHIVE" ] \
			|| { echo "ERROR: no local gcc-${pkgver}.tar.xz and no fetched SOURCE_ARCHIVE" >&2; return 1; }
		GCCBALL=$SOURCE_ARCHIVE
	fi
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$GCCBALL"
	# The AKADATA branch-cost backport is an x86 policy, applied only
	# where it means something (see the BRANCH_COST_NOTE derivation
	# above). Unconditional on every arch would carry dead weight at
	# best and a hardware-wrong claim at worst.
	if [ "$pkgarch" = x86_64 ]; then
		patch -d "$SRC" -Np1 \
			-i "$RECIPE_DIR/files/0001-x86-increase-generic-tune-branch-misprediction-cost.patch"
	fi
	patch -d "$SRC" -Np1 \
		-i "$RECIPE_DIR/files/0002-m64-multilib-osdir-lib-not-lib64.patch"
	mkdir -p "$BUILDDIR"
	cd "$BUILDDIR"
	# Same-version --disable-bootstrap build: our published gcc 16.1.0
	# compiles this tree directly (no 3-stage dance, no foreign toolchain).
	../source/configure \
		--build="$ARCH_TRIPLET" \
		--host="$ARCH_TRIPLET" \
		--target="$ARCH_TRIPLET" \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--with-sysroot=/ \
		--with-toolexeclibdir=/usr/lib \
		--with-native-system-header-dir=/usr/include \
		--with-arch="$GCC_ARCH" \
		--with-tune=generic \
		--with-gmp=/usr \
		--with-mpfr=/usr \
		--with-mpc=/usr \
		--with-isl=/usr \
		--with-system-zlib \
		--with-pkgversion="Saphira ${pkgver} (${BRANCH_COST_NOTE}, lib-only layout)" \
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

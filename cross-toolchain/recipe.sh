#!/bin/sh

# Saphira cross-toolchain framework: request a target architecture, get a
# complete cross compiler. One recipe, shared build logic, per-target
# variables in the case block below - a new target reuses the framework
# by adding variables, never by cloning build logic. No machine policy
# lives here (no -march/-mcpu, no board kernels): the triplet is the ABI
# target, machine profiles select codegen later.
#
#   SAPHIRA_CROSS_TARGET=aarch64-akadata-linux-musl  (default)
#   SAPHIRA_CROSS_TARGET=riscv64-akadata-linux-musl
#
# Pipeline (single transaction, deterministic sysroot, build==host so no
# Canadian cross staging): target binutils -> bootstrap C-only GCC ->
# target kernel headers + musl into the sysroot -> final C/C++ GCC.
# Installs only <triplet>-prefixed tools plus the target sysroot; the
# native compiler closure is never touched (asserted: no unprefixed
# compiler binaries in the payload).

CROSS_TARGET=${SAPHIRA_CROSS_TARGET:-aarch64-akadata-linux-musl}
case "$CROSS_TARGET" in
aarch64-akadata-linux-musl)
	KARCH=arm64
	# readelf "Machine:" line and musl loader name for the smoke tests.
	EXPECT_MACHINE=AArch64
	TARGET_INTERP=/lib/ld-musl-aarch64.so.1
	;;
riscv64-akadata-linux-musl)
	KARCH=riscv
	EXPECT_MACHINE="RISC-V"
	TARGET_INTERP=/lib/ld-musl-riscv64.so.1
	;;
*)
	echo "ERROR: unknown SAPHIRA_CROSS_TARGET: $CROSS_TARGET" >&2
	return 1
	;;
esac

pkgname=cross-toolchain
pkgver=1.0
pkgrel=2
# NOTE (single-variant discipline, mirrors the SAPHIRA_GCC_VERSION
# precedent): one recipe dir builds one target at a time - the package
# name is fixed because resolvepkg requires directory == pkgname.
# Switching SAPHIRA_CROSS_TARGET changes the payload under the same
# NVR, so a target switch MUST bump pkgrel (immutable-filename rule);
# the superseded target's bytes stay in hatchling history. Targets do
# not co-install; build hosts target one arch per generation.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Cross toolchain for $CROSS_TARGET (binutils, GCC C/C++, musl sysroot)"
license='GPL-3.0-or-later WITH GCC Runtime Library Exception'
origin=cross-toolchain
repo=saphira
url=https://gcc.gnu.org/

# Aligned with the native Saphira toolchain wherever practical: same GCC,
# binutils, musl and kernel-headers generations. vendor=+sha256= carries
# the primary (GCC) source on the builder fetch path; the remaining three
# are fetched+verified in-recipe (single-fetch builder contract) with a
# files/ override each, honoring the shared source cache when present.
GCC_VER=16.2.0
vendor=https://ftp.gnu.org/gnu/gcc/gcc-16.2.0/gcc-16.2.0.tar.xz
sha256=e6738e29597f733270731aa90600f37ffdc045079dfc27ec7e8192cc81085c3e
BINUTILS_VER=2.46.1
BINUTILS_URL=https://ftp.gnu.org/gnu/binutils/binutils-2.46.1.tar.xz
BINUTILS_SHA256=e127a709cba24c76de8936cb7083dd768f28cd37eb010492e2f19b71eb1294e4
MUSL_VER=1.2.6
MUSL_URL=https://musl.libc.org/releases/musl-1.2.6.tar.gz
MUSL_SHA256=d585fd3b613c66151fc3249e8ed44f77020cb5e6c1e635a616d3f9f82460512a
KERNEL_VER=7.1.5
KERNEL_URL=https://mirrors.edge.kernel.org/pub/linux/kernel/v7.x/linux-7.1.5.tar.xz
KERNEL_SHA256=22a0196b3cbcdf34dc27b77561f4d040585fd3447edc9ab3531a1ac79e3041e7

# Driver binaries are native x86_64 (build==host); the sysroot is the
# only target-arch payload. Mirrors the native gcc runtime closure.
depends="
    binutils
    gcc-libs
    gmp
    isl
    mpc
    mpfr
    zlib
    zstd
"

makedepends="
    binutils
    bison
    curl
    flex
    gawk
    gcc
    gmp-dev
    isl-dev
    m4
    make
    mpc-dev
    mpfr-dev
    perl
    pkgconf
    python3
    rsync
    zlib-dev
    zstd-dev
"

# No -doc split: cross info/man pages and GDB pretty-printers duplicate
# the identical-version native docs, so usr/share is pruned wholesale.
SYSROOT_ABS=/usr/$CROSS_TARGET/sysroot
TOOLEXECLIB=$SYSROOT_ABS/lib

# fetch_verified <url> <sha256> <dest>: files/ override wins (verified),
# else shared cache hit (verified), else curl with retries (verified,
# best-effort cache populate). Fail-closed on any mismatch. Local
# override filenames (drop any of these into files/ to build offline):
#   files/gcc-16.2.0.tar.xz
#   files/binutils-2.46.1.tar.xz
#   files/musl-1.2.6.tar.gz
#   files/linux-7.1.5.tar.xz
fetch_verified()
{
	local url=$1 sha=$2 dest=$3
	local base localball cache ctmp
	base=${url##*/}
	localball="$RECIPE_DIR/files/$base"
	if [ -f "$localball" ]; then
		echo "$sha  $localball" | sha256sum -c - || return 1
		cp -- "$localball" "$dest"
		return 0
	fi
	cache=${SAPHIRA_SOURCE_CACHE-}
	if [ -n "$cache" ] && [ -f "$cache/$sha" ]; then
		echo "$sha  $cache/$sha" | sha256sum -c - || return 1
		cp -- "$cache/$sha" "$dest"
		return 0
	fi
	curl -fL --retry 3 --output "$dest" "$url" || return 1
	echo "$sha  $dest" | sha256sum -c - || { rm -f -- "$dest"; return 1; }
	if [ -n "$cache" ]; then
		ctmp=$cache/.tmp.$$.download
		cp -- "$dest" "$ctmp" 2>/dev/null && mv -- "$ctmp" "$cache/$sha" 2>/dev/null || true
	fi
}

# unpack_verified <url> <sha256> <destdir>: fetch then extract a single
# top-level tree, stripped, into destdir. The destination exists before
# the fetch: curl cannot create missing parents and fails writing the
# download (rc=23), which once failed a full cross build at the first
# in-recipe fetch.
unpack_verified()
{
	local url=$1 sha=$2 destdir=$3
	local dl
	mkdir -p "$destdir"
	dl=$destdir/.dl-$(basename "$url")
	fetch_verified "$url" "$sha" "$dl" || return 1
	tar --no-same-owner -C "$destdir" --strip-components=1 -xf "$dl"
	rm -f -- "$dl"
}

recipe_build()
{
	# Build host: explicit override wins, else the native compiler's own
	# triplet. Lazy (inside recipe_build) because top-level command
	# substitution would execute in the resolvepkg metadata probe
	# sandbox. Allowlisted: x86_64 (egg), aarch64 (armer), riscv64
	# (later). The same recipe bootstraps ARM from x86_64 today and
	# rebuilds natively on ARM tomorrow - with build==host==target the
	# stages below still work, and --program-prefix keeps every binary
	# triplet-prefixed so a native rebuild never shadows native gcc.
	# (On non-Saphira hosts such as Alpine/armer today, gcc
	# -dumpmachine reports a foreign triplet: set SAPHIRA_HOST_TRIPLET
	# explicitly there.)
	HOST_TRIPLET=${SAPHIRA_HOST_TRIPLET:-$(gcc -dumpmachine)}
	case "$HOST_TRIPLET" in
	x86_64-akadata-linux-musl|aarch64-akadata-linux-musl|riscv64-akadata-linux-musl) ;;
	*)
		echo "ERROR: unsupported build host: $HOST_TRIPLET" >&2
		return 1
		;;
	esac
	PROGRAM_PREFIX=
	if [ "$HOST_TRIPLET" = "$CROSS_TARGET" ]; then
		PROGRAM_PREFIX=--program-prefix=$CROSS_TARGET-
	fi
	PKGVER="Saphira cross $CROSS_TARGET (gcc $GCC_VER)"
	export PATH="$PKGDEST/usr/bin:$PATH"

	# The builder pre-extracted the vendor= (GCC) fetch to $SRC; the
	# remaining sources land in $BUILDDIR/extra-sources - NEVER as
	# subdirectories of the GCC tree. GCC's configure scans srcdir for
	# known subdirs, and a $SRC/binutils directory makes it conclude a
	# combined tree is being built: it then points AR/RANLIB_FOR_TARGET
	# at the unbuilt in-tree ./binutils/ar and every target-lib link
	# fails. That misdetection cost a full bootstrap cycle to diagnose;
	# the layout rule is: the GCC tree contains only GCC.
	DEPSRC=$BUILDDIR/extra-sources
	GCCBALL="$RECIPE_DIR/files/gcc-$GCC_VER.tar.xz"
	if [ -f "$GCCBALL" ]; then
		echo "$sha256  $GCCBALL" | sha256sum -c -
		tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$GCCBALL"
	fi
	# Saphira layout policy, per-target edition (mirrors the native
	# i386/t-linux64 patch): the aarch64 lp64 osdir is ../lib, not
	# ../lib64, or --with-toolexeclibdir=<sysroot>/lib is rewritten to
	# <sysroot>/lib/../lib64. Guarded per target: riscv64 carries its
	# own t-linux default, verified when that target builds.
	case "$CROSS_TARGET" in
	aarch64-*)
		patch -d "$SRC" -Np1 -i "$RECIPE_DIR/files/0001-aarch64-lp64-osdir-lib-not-lib64.patch"
		;;
	esac
	unpack_verified "$BINUTILS_URL" "$BINUTILS_SHA256" "$DEPSRC/binutils"
	unpack_verified "$MUSL_URL" "$MUSL_SHA256" "$DEPSRC/musl"
	unpack_verified "$KERNEL_URL" "$KERNEL_SHA256" "$DEPSRC/linux"
	mkdir -p "$BUILDDIR/binutils" "$BUILDDIR/gcc-boot" "$BUILDDIR/gcc-final"

	# Stage 1: target binutils (native build tools only).
	cd "$BUILDDIR/binutils"
	"$DEPSRC/binutils/configure" \
		--prefix=/usr \
		--with-sysroot=$SYSROOT_ABS \
		--build=$HOST_TRIPLET --host=$HOST_TRIPLET --target=$CROSS_TARGET \
		$PROGRAM_PREFIX \
		--disable-multilib --disable-nls --disable-werror --disable-gdb \
		--enable-64-bit-bfd --enable-default-pie \
		--enable-ld=default --enable-plugins \
		--with-system-zlib \
		--with-pkgversion="$PKGVER"
	make -j${JOBS:-$(nproc)}
	make DESTDIR="$PKGDEST" install
	rm -f "$PKGDEST"/usr/lib/*.la
	# bfd-plugins/libdep.so is a HOST-arch linker plugin served from the
	# shared default plugin dir: the native binutils package (same
	# version, same host arch) already owns it, and the cross ld finds
	# it there. Shipping a second copy would collide and risk version
	# skew inside the plugin search path. LTO is unaffected (explicit
	# liblto_plugin from the triplet libexec dir).
	rm -rf "$PKGDEST/usr/lib/bfd-plugins"

	# Stage 2: bootstrap C-only GCC (no libc yet: no headers, no threads,
	# no shared target libs). Installed to the final prefix; the final
	# stage overwrites/extends it.
	cd "$BUILDDIR/gcc-boot"
	"$SRC/configure" \
		--prefix=/usr \
		--with-sysroot=$SYSROOT_ABS \
		--build=$HOST_TRIPLET --host=$HOST_TRIPLET --target=$CROSS_TARGET \
		$PROGRAM_PREFIX \
		--enable-languages=c \
		--without-headers --with-newlib \
		--disable-shared --disable-threads \
		--disable-libatomic --disable-libgomp --disable-libquadmath \
		--disable-libcc1 --disable-libsanitizer --disable-libssp --disable-libvtv --disable-libitm \
		--disable-bootstrap --disable-multilib --disable-nls --disable-analyzer \
		--disable-werror --disable-fixincludes \
		--with-gmp=/usr --with-mpfr=/usr --with-mpc=/usr --with-isl=/usr \
		--with-system-zlib \
		--with-pkgversion="$PKGVER"
	# INHIBIT_LIBC_CFLAGS is the documented freestanding escape hatch
	# (tsystem.h skips all libc headers with it): upstream configure no
	# longer sets it automatically, so the bootstrap passes it
	# explicitly - without it every libgcc2 object dies on missing
	# stdio.h with no target libc installed yet.
	make -j${JOBS:-$(nproc)} INHIBIT_LIBC_CFLAGS=-Dinhibit_libc all-gcc all-target-libgcc
	make DESTDIR="$PKGDEST" install-gcc install-target-libgcc

	# Stage 3a: target kernel headers into the sysroot (same generation
	# as the native SDK; headers-0003 is arch-independent).
	SYSSTAGE="$PKGDEST$SYSROOT_ABS"
	mkdir -p "$SYSSTAGE"
	patch -d "$DEPSRC/linux" -Np1 -i "$RECIPE_DIR/files/0003-libc-compat-musl-netinet-in-coordination.patch"
	make -C "$DEPSRC/linux" ARCH=$KARCH mrproper headers
	make -C "$DEPSRC/linux" ARCH=$KARCH INSTALL_HDR_PATH="$SYSSTAGE/usr" headers_install

	# Stage 3b: target musl into the sysroot (same tree policy as native:
	# 1MiB default stack, kernel-uapi coordination; loader lands in the
	# sysroot /lib, Saphira-clean like the native layout).
	patch -d "$DEPSRC/musl" -Np1 -i "$RECIPE_DIR/files/0001-default-pthread-stack-1MiB.patch"
	patch -d "$DEPSRC/musl" -Np1 -i "$RECIPE_DIR/files/0002-netinet-in6-kernel-uapi-coordination.patch"
	cd "$DEPSRC/musl"
	CC=$CROSS_TARGET-gcc CROSS_COMPILE=$CROSS_TARGET- \
		./configure --prefix=/usr --syslibdir=/lib
	make -j${JOBS:-$(nproc)}
	make DESTDIR="$SYSSTAGE" install

	# Stage 4: final C/C++ GCC against the populated sysroot. Target
	# runtimes (libgcc_s, libstdc++) install into the sysroot lib so
	# --sysroot linking finds them; no unprefixed binaries may appear.
	# --with-sysroot is the baked-in final path for the INSTALLED
	# compiler, but at build time the populated sysroot only exists
	# under $PKGDEST staging: --with-build-sysroot points the target-
	# library builds there (without it, libgcc/libstdc++ compile
	# against the nonexistent final path and die on missing stdio.h).
	# --with-build-sysroot is build-time-only and never installed.
	cd "$BUILDDIR/gcc-final"
	"$SRC/configure" \
		--prefix=/usr \
		--with-sysroot=$SYSROOT_ABS \
		--with-build-sysroot="$PKGDEST$SYSROOT_ABS" \
		--with-toolexeclibdir=$TOOLEXECLIB \
		--with-native-system-header-dir=/usr/include \
		--build=$HOST_TRIPLET --host=$HOST_TRIPLET --target=$CROSS_TARGET \
		$PROGRAM_PREFIX \
		--enable-languages=c,c++ \
		--enable-threads=posix \
		--enable-shared \
		--enable-libatomic --enable-libgomp \
		--disable-libquadmath \
		--disable-libcc1 --disable-libsanitizer --disable-libssp --disable-libvtv --disable-libitm \
		--disable-bootstrap --disable-multilib --disable-nls --disable-analyzer \
		--disable-werror --disable-fixincludes \
		--with-gmp=/usr --with-mpfr=/usr --with-mpc=/usr --with-isl=/usr \
		--with-system-zlib \
		--with-pkgversion="$PKGVER"
	make -j${JOBS:-$(nproc)}
	make DESTDIR="$PKGDEST" install
	rm -f "$PKGDEST"/usr/lib/*.la
	rm -f "$PKGDEST$SYSROOT_ABS"/lib/*.la "$PKGDEST$SYSROOT_ABS"/usr/lib/*.la
	# info/man pages and GDB pretty-printers duplicate the
	# identical-version native docs: prune the whole share tree (there
	# is no -doc split for this recipe by design).
	rm -rf "$PKGDEST/usr/share"
	# Saphira forbids lib64/usr/lib64 anywhere in seeds and payloads;
	# merge-away guard (native gcc recipe pattern), then fail closed.
	for lib64 in "$PKGDEST"/lib64 "$PKGDEST"/usr/lib64; do
		if [ -e "$lib64" ]; then
			cp -a "$lib64"/. "$PKGDEST/usr/lib/" 2>/dev/null || true
			rm -rf -- "$lib64"
		fi
	done
	if find "$PKGDEST" -name '*lib64*' | grep -q .; then
		echo "ERROR: lib64 remnants in cross payload" >&2
		return 1
	fi
	if [ -e "$PKGDEST/usr/bin/gcc" ] || [ -e "$PKGDEST/usr/bin/cc" ] \
		|| [ -e "$PKGDEST/usr/bin/g++" ]; then
		echo "ERROR: unprefixed compiler binaries would shadow native gcc" >&2
		return 1
	fi

	# Fail-closed allowed-root policy: every payload file must live
	# under a triplet-namespaced root. Anything else (unprefixed host
	# libs, plugin dirs, docs that escaped pruning) stops the build
	# here instead of dying later at the signer ownership gate.
	badpaths=$(cd "$PKGDEST" && find . \( -type f -o -type l \) \
		! -path "./usr/bin/$CROSS_TARGET-*" \
		! -path "./usr/lib/gcc/$CROSS_TARGET/*" \
		! -path "./usr/libexec/gcc/$CROSS_TARGET/*" \
		! -path "./usr/$CROSS_TARGET/*")
	if [ -n "$badpaths" ]; then
		echo "ERROR: files outside the permitted cross roots:" >&2
		echo "$badpaths" >&2
		return 1
	fi

	# Smoke: trivial C and C++ compile+link, static and dynamic, against
	# the STAGED sysroot (the baked-in final path does not exist yet).
	# Fail-closed on machine, interpreter, or missing prefixed tools.
	TC="$PKGDEST/usr/bin/$CROSS_TARGET"
	SYS="--sysroot=$SYSSTAGE"
	for tool in gcc g++ ld as ar strip; do
		[ -x "$TC-$tool" ] || { echo "ERROR: missing $CROSS_TARGET-$tool" >&2; return 1; }
	done
	mkdir -p "$BUILDDIR/smoke"
	cd "$BUILDDIR/smoke"
	printf '%s\n' '#include <stdio.h>' 'int main(void){printf("hi\n");return 0;}' > smoke.c
	printf '%s\n' '#include <iostream>' 'int main(){std::cout<<"hi\n";return 0;}' > smoke.cc
	"$TC-gcc" $SYS smoke.c -o smoke-dyn
	"$TC-gcc" $SYS smoke.c -static -o smoke-static
	"$TC-g++" $SYS smoke.cc -o smoke-cc
	[ "$(readelf -h smoke-dyn | grep 'Machine:' | grep -c "$EXPECT_MACHINE")" -eq 1 ] \
		|| { echo "ERROR: unexpected ELF machine:" >&2; readelf -h smoke-dyn >&2; return 1; }
	[ "$(readelf -lW smoke-dyn | grep -oE '/[^ ]*ld-musl-[^ ]*\.so\.1' | head -1)" = "$TARGET_INTERP" ] \
		|| { echo "ERROR: unexpected dynamic interpreter:" >&2; readelf -lW smoke-dyn >&2; return 1; }
	readelf -h "$SYSSTAGE/usr/lib/libc.so" | grep -q "$EXPECT_MACHINE" \
		|| { echo "ERROR: sysroot libc is not a $CROSS_TARGET object" >&2; return 1; }
	# musl installs the loader as an absolute symlink to its libc (stock
	# upstream layout); it must exist and resolve inside the sysroot.
	test -L "$SYSSTAGE/lib/ld-musl-${CROSS_TARGET%%-*}.so.1" \
		|| { echo "ERROR: sysroot loader link missing" >&2; return 1; }
}

recipe_install()
{
	# Everything was installed to its final layout during recipe_build
	# (staged prefix + sysroot); nothing left to move.
	:
}

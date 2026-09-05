#!/bin/sh

pkgname=libc++
pkgver=22.1.8
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="LLVM libc++: C++ standard library"
license="Apache-2.0 WITH LLVM-exception"
origin=libc++
repo=saphira
url=https://libcxx.llvm.org/
source=https://github.com/llvm/llvm-project/releases/download/llvmorg-22.1.8/llvm-project-22.1.8.src.tar.xz
sha256=922f1817a0df7b1489272d18134ee0087a8b068828f87ac63b9861b1a9965888

depends="
    libunwind>=22.1.8-r1
"

makedepends="
    binutils
    clang>=22.1.8-r1
    cmake
    compiler-rt>=22.1.8-r1
    gcc
    ninja
    python3
"

# Proven v0 flags: runtimes build driven by the native clang with the
# Saphira musl triple, building unwind+cxxabi+cxx together; musl libc
# mode, compiler-rt builtins, LLVM unwinder, no ABI linker script,
# static and shared libraries installed, tests/benchmarks/docs off.
# Note: like in v0, the combined runtimes install also stages libunwind
# and libc++abi copies; those overlap the standalone libunwind/libc++abi
# packages at the same version.
recipe_build()
{
	cmake -G Ninja "$SRC/runtimes" -B "$BUILDDIR" \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_BUILD_TYPE=Release -DCMAKE_SKIP_RPATH=ON \
		-DCMAKE_C_COMPILER=clang \
		-DCMAKE_CXX_COMPILER=clang++ \
		-DCMAKE_ASM_COMPILER=clang \
		-DCMAKE_C_COMPILER_TARGET=x86_64-akadata-linux-musl \
		-DCMAKE_CXX_COMPILER_TARGET=x86_64-akadata-linux-musl \
		-DCMAKE_ASM_COMPILER_TARGET=x86_64-akadata-linux-musl \
		-DCMAKE_C_FLAGS="${CFLAGS-}" -DCMAKE_CXX_FLAGS="${CXXFLAGS-}" \
		-DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS-}" \
		-DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS-}" \
		-DLLVM_DEFAULT_TARGET_TRIPLE=x86_64-akadata-linux-musl \
		-DLLVM_ENABLE_RUNTIMES='libunwind;libcxxabi;libcxx' \
		-DLLVM_INCLUDE_TESTS=OFF \
		-DLIBCXX_INCLUDE_BENCHMARKS=OFF -DLIBCXX_INCLUDE_DOCS=OFF \
		-DLIBCXXABI_INCLUDE_TESTS=OFF -DLIBUNWIND_INCLUDE_TESTS=OFF \
		-DLIBCXXABI_ENABLE_ASSERTIONS=OFF -DLIBUNWIND_ENABLE_ASSERTIONS=OFF \
		-DLIBCXXABI_USE_LLVM_UNWINDER=ON \
		-DLIBCXXABI_USE_COMPILER_RT=ON -DLIBUNWIND_USE_COMPILER_RT=ON \
		-DLIBCXX_USE_COMPILER_RT=ON -DLIBCXX_HAS_MUSL_LIBC=ON \
		-DLIBCXX_ENABLE_ABI_LINKER_SCRIPT=OFF \
		-DLIBCXXABI_INSTALL_STATIC_LIBRARY=ON -DLIBUNWIND_INSTALL_STATIC_LIBRARY=ON \
		-DLIBCXXABI_INSTALL_SHARED_LIBRARY=ON -DLIBUNWIND_INSTALL_SHARED_LIBRARY=ON \
		-DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=OFF \
		-DLIBCXX_INSTALL_STATIC_LIBRARY=ON \
		-DLIBCXX_INSTALL_SHARED_LIBRARY=ON
	ninja -C "$BUILDDIR" unwind cxxabi cxx
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install
	# The standalone libc++abi/libunwind packages own their files; the
	# combined runtimes install must not double-ship them (upgrade
	# overwrite errors). This covers libs, static archives and headers
	# (libunwind-dev also owns its headers; libc++abi's headers would
	# collide with a future libc++abi publish - both are stripped).
	rm -rf "$PKGDEST/usr/lib/libc++abi.so"* "$PKGDEST/usr/lib/libunwind.so"* \
	       "$PKGDEST/usr/lib/libc++abi.a" "$PKGDEST/usr/lib/libunwind.a" \
	       "$PKGDEST/usr/include/mach-o" \
	       "$PKGDEST/usr/include/libunwind.h" \
	       "$PKGDEST/usr/include/__libunwind_config.h" \
	       "$PKGDEST/usr/include/libunwind.modulemap" \
	       "$PKGDEST/usr/include/unwind.h" \
	       "$PKGDEST/usr/include/unwind_arm_ehabi.h" \
	       "$PKGDEST/usr/include/unwind_itanium.h" \
	       "$PKGDEST/usr/include/cxxabi.h" \
	       "$PKGDEST/usr/include/__cxxabi_config.h"
	install -D -m 0644 "$SRC/libcxx/LICENSE.TXT" \
		"$PKGDEST/usr/share/licenses/libc++/LICENSE.TXT"
	# Proven v0 leak check: no build paths may survive in ELF metadata.
	find "$PKGDEST" -type f -print | while IFS= read -r file; do
		if readelf -d "$file" 2>/dev/null |
			grep -Eq '(RPATH|RUNPATH).*(/var/tmp|/mnt/akadata|/out/rootfs|/out/sysroot|/build)'; then
			printf 'libc++: build path leaked into %s\n' "$file" >&2
			exit 1
		fi
	done
}

#!/bin/sh

pkgname=libc++abi
pkgver=22.1.8
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="LLVM libc++abi: low-level C++ ABI runtime"
license="Apache-2.0 WITH LLVM-exception"
origin=libc++abi
repo=saphira
url=https://libcxxabi.llvm.org/
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
    gettext
    libunwind-dev>=22.1.8-r1
    ninja
    python3
"

# Combined-runtimes configure (libc++ recipe precedent): the standalone
# cxxabi-only configure fails on generated libcxx headers (__config,
# version) — three failed builds Sep-Oct (rc=1 in cmake/ninja, never in
# packaging). Configuring libunwind+libcxxabi+libcxx together generates
# them; we still build and install ONLY the cxxabi target, so this
# package owns exactly the ABI runtime and nothing else. Native clang,
# Saphira musl target, LLVM unwinder, compiler-rt, tests off.
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
		-DLIBCXXABI_ENABLE_ASSERTIONS=OFF \
		-DLIBUNWIND_ENABLE_ASSERTIONS=OFF \
		-DLIBCXXABI_USE_LLVM_UNWINDER=ON \
		-DLIBCXXABI_USE_COMPILER_RT=ON -DLIBUNWIND_USE_COMPILER_RT=ON \
		-DLIBCXX_USE_COMPILER_RT=ON -DLIBCXX_HAS_MUSL_LIBC=ON \
		-DLIBCXX_ENABLE_ABI_LINKER_SCRIPT=OFF \
		-DLIBCXXABI_INSTALL_STATIC_LIBRARY=ON \
		-DLIBCXXABI_INSTALL_SHARED_LIBRARY=ON
	ninja -C "$BUILDDIR" cxxabi
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install-cxxabi
	# Ownership split (collision-proven 2026-10-28): the two c++/v1
	# cxxabi headers stay with the libc++ package, which stages them
	# from the same combined runtimes build and already publishes them
	# (signing refuses dual-owned paths). This package ships the ABI
	# runtime (shared + static) only.
	rm -rf "$PKGDEST/usr/include/c++/v1/__cxxabi_config.h" \
	       "$PKGDEST/usr/include/c++/v1/cxxabi.h"
	install -D -m 0644 "$SRC/libcxxabi/LICENSE.TXT" \
		"$PKGDEST/usr/share/licenses/libc++abi/LICENSE.TXT"
	# Proven v0 leak check: no build paths may survive in ELF metadata.
	find "$PKGDEST" -type f -print | while IFS= read -r file; do
		if readelf -d "$file" 2>/dev/null |
			grep -Eq '(RPATH|RUNPATH).*(/var/tmp|/mnt/akadata|/out/rootfs|/out/sysroot|/build)'; then
			printf 'libc++abi: build path leaked into %s\n' "$file" >&2
			exit 1
		fi
	done
}

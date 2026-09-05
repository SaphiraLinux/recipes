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
    libunwind-dev>=22.1.8-r1
    ninja
    python3
"

# Proven v0 flags: runtimes build driven by the native clang with the
# Saphira musl target, LLVM libunwind as the unwinder, compiler-rt
# builtins, static and shared c++abi installed, tests/assertions off.
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
		-DLLVM_ENABLE_RUNTIMES='libunwind;libcxxabi' \
		-DLIBCXXABI_INCLUDE_TESTS=OFF -DLIBCXXABI_ENABLE_ASSERTIONS=OFF \
		-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
		-DLIBCXXABI_USE_LLVM_UNWINDER=ON \
		-DLIBCXXABI_LIBCXX_INCLUDES=$SRC/libcxx/include \
		-DLIBCXXABI_LIBUNWIND_INCLUDES=/usr/include \
		-DLIBCXXABI_USE_COMPILER_RT=ON \
		-DLIBCXXABI_INSTALL_STATIC_LIBRARY=ON \
		-DLIBCXXABI_INSTALL_SHARED_LIBRARY=ON
	ninja -C "$BUILDDIR" cxxabi
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install-cxxabi
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

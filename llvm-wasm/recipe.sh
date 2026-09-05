#!/bin/sh

pkgname=llvm-wasm
pkgver=22.1.8
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="LLVM for the Emscripten toolchain: X86+WebAssembly backends under /usr/lib/emscripten-toolchain"
license="Apache-2.0 WITH LLVM-exception"
origin=llvm-wasm
repo=saphira
url=https://llvm.org/
source=https://github.com/llvm/llvm-project/releases/download/llvmorg-22.1.8/llvm-project-22.1.8.src.tar.xz
sha256=922f1817a0df7b1489272d18134ee0087a8b068828f87ac63b9861b1a9965888

depends=""

makedepends="
    binutils
    cmake
    gcc
    libffi-dev
    libxml2-dev
    ninja
    python3
    zlib-dev
    zstd-dev
"

# Proven v0 flags: separate LLVM install under /usr/lib/emscripten-
# toolchain with $ORIGIN-relative RPATH, X86+WebAssembly targets, shared
# libLLVM dylib, system zlib/zstd/ffi/libxml2, utils installed,
# tests/benchmarks/examples/docs/bindings off.
recipe_build()
{
	cmake -G Ninja "$SRC/llvm" -B "$BUILDDIR" \
		-DCMAKE_INSTALL_PREFIX=/usr/lib/emscripten-toolchain \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_RPATH='$ORIGIN/../lib' \
		-DCMAKE_C_FLAGS="${CFLAGS-}" -DCMAKE_CXX_FLAGS="${CXXFLAGS-}" \
		-DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS-}" \
		-DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS-}" \
		-DLLVM_TARGETS_TO_BUILD='X86;WebAssembly' \
		-DLLVM_ENABLE_PROJECTS= -DLLVM_ENABLE_RUNTIMES= \
		-DLLVM_BUILD_LLVM_DYLIB=ON -DLLVM_LINK_LLVM_DYLIB=ON \
		-DLLVM_ENABLE_ZLIB=FORCE_ON -DLLVM_ENABLE_ZSTD=FORCE_ON \
		-DLLVM_ENABLE_FFI=ON -DLLVM_ENABLE_LIBXML2=FORCE_ON \
		-DLLVM_ENABLE_TERMINFO=OFF -DLLVM_INCLUDE_TESTS=OFF \
		-DLLVM_INCLUDE_BENCHMARKS=OFF -DLLVM_INCLUDE_EXAMPLES=OFF \
		-DLLVM_BUILD_DOCS=OFF -DLLVM_INSTALL_UTILS=ON \
		-DLLVM_ENABLE_BINDINGS=OFF
	ninja -C "$BUILDDIR"
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install
	"$PKGDEST/usr/lib/emscripten-toolchain/bin/llc" \
		--version | grep -Fq WebAssembly ||
		{ printf 'llvm-wasm: staged llc does not report the WebAssembly target\n' >&2; exit 1; }
	# Proven v0 leak check: no build paths may survive in ELF metadata.
	find "$PKGDEST" -type f -print | while IFS= read -r file; do
		if readelf -d "$file" 2>/dev/null |
			grep -Eq '(RPATH|RUNPATH).*(/var/tmp|/mnt/akadata|/out/rootfs|/out/sysroot|/build)'; then
			printf 'llvm-wasm: build path leaked into %s\n' "$file" >&2
			exit 1
		fi
	done
}

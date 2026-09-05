#!/bin/sh

pkgname=clang-wasm
pkgver=22.1.8
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Clang for the Emscripten toolchain under /usr/lib/emscripten-toolchain"
license="Apache-2.0 WITH LLVM-exception"
origin=clang-wasm
repo=saphira
url=https://clang.llvm.org/
source=https://github.com/llvm/llvm-project/releases/download/llvmorg-22.1.8/llvm-project-22.1.8.src.tar.xz
sha256=922f1817a0df7b1489272d18134ee0087a8b068828f87ac63b9861b1a9965888

depends="
    llvm-wasm>=22.1.8-r1
"

makedepends="
    binutils
    cmake
    gcc
    llvm-wasm>=22.1.8-r1
    ninja
    python3
    zlib-dev
    zstd-dev
    libxml2-dev
"

# Proven v0 flags: clang installed into the emscripten-toolchain prefix
# against the llvm-wasm cmake configs, linked via the clang shared
# library, $ORIGIN-relative RPATH, Saphira musl default/host triple,
# tests/examples/ARCMT/static-analyzer off. Verified by running the
# staged clang with the wasm32-unknown-emscripten target.
recipe_build()
{
	cmake -G Ninja "$SRC/clang" -B "$BUILDDIR" \
		-DCMAKE_INSTALL_PREFIX=/usr/lib/emscripten-toolchain \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_RPATH='$ORIGIN/../lib' \
		-DCMAKE_C_FLAGS="${CFLAGS-}" -DCMAKE_CXX_FLAGS="${CXXFLAGS-}" \
		-DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS-}" \
		-DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS-}" \
		-DLLVM_DIR=/usr/lib/emscripten-toolchain/lib/cmake/llvm \
		-DLLVM_INCLUDE_TESTS=OFF -DCLANG_INCLUDE_TESTS=OFF \
		-DCLANG_BUILD_EXAMPLES=OFF \
		-DCLANG_ENABLE_ARCMT=OFF -DCLANG_ENABLE_STATIC_ANALYZER=OFF \
		-DCLANG_LINK_CLANG_DYLIB=ON \
		-DLLVM_DEFAULT_TARGET_TRIPLE=x86_64-akadata-linux-musl \
		-DLLVM_HOST_TRIPLE=x86_64-akadata-linux-musl
	ninja -C "$BUILDDIR"
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install
	LD_LIBRARY_PATH="$PKGDEST/usr/lib/emscripten-toolchain/lib:/usr/lib/emscripten-toolchain/lib" \
		"$PKGDEST/usr/lib/emscripten-toolchain/bin/clang" \
		--target=wasm32-unknown-emscripten -print-target-triple |
		grep -Fqx wasm32-unknown-emscripten ||
		{ printf 'clang-wasm: staged clang does not target wasm32-unknown-emscripten\n' >&2; exit 1; }
	# Proven v0 leak check: no build paths may survive in ELF metadata.
	find "$PKGDEST" -type f -print | while IFS= read -r file; do
		if readelf -d "$file" 2>/dev/null |
			grep -Eq '(RPATH|RUNPATH).*(/var/tmp|/mnt/akadata|/out/rootfs|/out/sysroot|/build)'; then
			printf 'clang-wasm: build path leaked into %s\n' "$file" >&2
			exit 1
		fi
	done
}

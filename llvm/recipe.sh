#!/bin/sh

pkgname=llvm
pkgver=22.1.8
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Low Level Virtual Machine: compiler infrastructure (LLVM core)"
license="Apache-2.0 WITH LLVM-exception"
origin=llvm
repo=main
url=https://llvm.org/
source=https://github.com/llvm/llvm-project/releases/download/llvmorg-22.1.8/llvm-project-22.1.8.src.tar.xz
sha256=922f1817a0df7b1489272d18134ee0087a8b068828f87ac63b9861b1a9965888

# Runtime deps: libLLVM-22.so links system libxml2/libffi/zlib directly;
# r1 shipped without this block (staged-builder era derived it), which
# broke clean-root consumers (rustc/ripgrep: undefined libxml2 refs).
depends="
    libffi
    libxml2
    zlib
"

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

# Proven v0 flags: X86-only backend, shared libLLVM dylib, Saphira musl
# triple, system zlib/zstd/ffi/libxml2, no docs/tests/benchmarks.
recipe_build()
{
	cmake -G Ninja "$SRC/llvm" -B "$BUILDDIR" \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_SKIP_RPATH=ON \
		-DCMAKE_C_FLAGS="${CFLAGS-}" \
		-DCMAKE_CXX_FLAGS="${CXXFLAGS-}" \
		-DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS-}" \
		-DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS-}" \
		-DLLVM_TARGETS_TO_BUILD=X86 \
		-DLLVM_ENABLE_PROJECTS= \
		-DLLVM_ENABLE_RUNTIMES= \
		-DLLVM_BUILD_LLVM_DYLIB=ON \
		-DLLVM_LINK_LLVM_DYLIB=ON \
		-DLLVM_DEFAULT_TARGET_TRIPLE=x86_64-akadata-linux-musl \
		-DLLVM_HOST_TRIPLE=x86_64-akadata-linux-musl \
		-DLLVM_ENABLE_ZLIB=FORCE_ON \
		-DLLVM_ENABLE_ZSTD=FORCE_ON \
		-DLLVM_ENABLE_FFI=ON \
		-DLLVM_ENABLE_LIBXML2=FORCE_ON \
		-DLLVM_ENABLE_TERMINFO=OFF \
		-DLLVM_INCLUDE_TESTS=OFF \
		-DLLVM_INCLUDE_BENCHMARKS=OFF \
		-DLLVM_INCLUDE_EXAMPLES=OFF \
		-DLLVM_BUILD_DOCS=OFF \
		-DLLVM_INSTALL_UTILS=ON \
		-DLLVM_ENABLE_BINDINGS=OFF
	ninja -C "$BUILDDIR"
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install
	install -D -m 0644 "$SRC/llvm/LICENSE.TXT" \
		"$PKGDEST/usr/share/licenses/llvm/LICENSE.TXT"
	install -d "$PKGDEST/usr/share/doc/llvm"
	cp -a "$SRC/llvm/docs" "$SRC/llvm/README.txt" \
		"$PKGDEST/usr/share/doc/llvm/"
	# Proven v0 leak check: no build paths may survive in ELF metadata.
	find "$PKGDEST" -type f -print | while IFS= read -r file; do
		if readelf -d "$file" 2>/dev/null |
			grep -Eq '(RPATH|RUNPATH).*(/var/tmp|/mnt/akadata|/out/rootfs|/out/sysroot|/build)'; then
			printf 'llvm: build path leaked into %s\n' "$file" >&2
			exit 1
		fi
	done
}

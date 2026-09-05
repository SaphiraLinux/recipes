#!/bin/sh

pkgname=clang
pkgver=22.1.8
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="C language family frontend for LLVM (clang and clang++)"
license="Apache-2.0 WITH LLVM-exception"
origin=clang
repo=saphira
url=https://clang.llvm.org/
source=https://github.com/llvm/llvm-project/releases/download/llvmorg-22.1.8/llvm-project-22.1.8.src.tar.xz
sha256=922f1817a0df7b1489272d18134ee0087a8b068828f87ac63b9861b1a9965888

depends="
    llvm>=22.1.8-r1
"

makedepends="
    binutils
    cmake
    gcc
    llvm>=22.1.8-r1
    ninja
    python3
    zlib-dev
    zstd-dev
    libxml2-dev
"

# Proven v0 flags: separate clang build against the installed LLVM,
# linked against libclang.dylib-style shared library; tests/examples
# off; static analyzer on. libclang.so and clang-c headers are removed
# at install exactly as in v0 (libclang is a separate future port).
recipe_build()
{
	cmake -G Ninja "$SRC/clang" -B "$BUILDDIR" \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_SKIP_RPATH=ON \
		-DCMAKE_C_FLAGS="${CFLAGS-}" \
		-DCMAKE_CXX_FLAGS="${CXXFLAGS-}" \
		-DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS-}" \
		-DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS-}" \
		-DLLVM_DIR=/usr/lib/cmake/llvm \
		-DLLVM_INCLUDE_TESTS=OFF \
		-DLLVM_INCLUDE_BENCHMARKS=OFF \
		-DCLANG_INCLUDE_TESTS=OFF \
		-DCLANG_BUILD_EXAMPLES=OFF \
		-DCLANG_ENABLE_ARCMT=OFF \
		-DCLANG_ENABLE_STATIC_ANALYZER=ON \
		-DCLANG_LINK_CLANG_DYLIB=ON
	ninja -C "$BUILDDIR"
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install
	target_triple=$(LD_LIBRARY_PATH="$PKGDEST/usr/lib:/usr/lib" \
		"$PKGDEST/usr/bin/clang" -print-target-triple) ||
		{ printf 'clang: unable to execute staged clang for target-triple validation\n' >&2; exit 1; }
	test "$target_triple" = x86_64-akadata-linux-musl ||
		{ printf 'clang: default target triple %s is not x86_64-akadata-linux-musl\n' "$target_triple" >&2; exit 1; }
	rm -f "$PKGDEST"/usr/lib/libclang.so*
	rm -rf "$PKGDEST/usr/include/clang-c"
	install -D -m 0644 "$SRC/clang/LICENSE.TXT" \
		"$PKGDEST/usr/share/licenses/clang/LICENSE.TXT"
	install -d "$PKGDEST/usr/share/doc/clang"
	cp -a "$SRC/clang/docs" "$SRC/clang/README.md" \
		"$PKGDEST/usr/share/doc/clang/"
	# Proven v0 leak check: no build paths may survive in ELF metadata.
	find "$PKGDEST" -type f -print | while IFS= read -r file; do
		if readelf -d "$file" 2>/dev/null |
			grep -Eq '(RPATH|RUNPATH).*(/var/tmp|/mnt/akadata|/out/rootfs|/out/sysroot|/build)'; then
			printf 'clang: build path leaked into %s\n' "$file" >&2
			exit 1
		fi
	done
}

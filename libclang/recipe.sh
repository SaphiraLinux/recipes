#!/bin/sh

pkgname=libclang
pkgver=22.1.8
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="libclang: stable C interface to the Clang frontend"
license="Apache-2.0 WITH LLVM-exception"
origin=libclang
repo=saphira
url=https://clang.llvm.org/
source=https://github.com/llvm/llvm-project/releases/download/llvmorg-22.1.8/llvm-project-22.1.8.src.tar.xz
sha256=922f1817a0df7b1489272d18134ee0087a8b068828f87ac63b9861b1a9965888

depends="
    llvm>=22.1.8-r1
"

makedepends="
    binutils
    clang>=22.1.8-r1
    cmake
    gcc
    llvm>=22.1.8-r1
    ninja
    python3
    zlib-dev
    zstd-dev
    libxml2-dev
"

# Proven v0 flags: standalone clang build against the installed LLVM
# with libclang as the only install target; ARCMT and static analyzer
# off; only clang-c headers kept under /usr/include.
recipe_build()
{
	cmake -G Ninja "$SRC/clang" -B "$BUILDDIR" \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_BUILD_TYPE=Release -DCMAKE_SKIP_RPATH=ON \
		-DCMAKE_C_FLAGS="${CFLAGS-}" -DCMAKE_CXX_FLAGS="${CXXFLAGS-}" \
		-DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS-}" \
		-DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS-}" \
		-DLLVM_DIR=/usr/lib/cmake/llvm -DLLVM_INCLUDE_TESTS=OFF \
		-DLLVM_INCLUDE_BENCHMARKS=OFF -DCLANG_INCLUDE_TESTS=OFF \
		-DCLANG_BUILD_EXAMPLES=OFF -DCLANG_ENABLE_ARCMT=OFF \
		-DCLANG_ENABLE_STATIC_ANALYZER=OFF
	ninja -C "$BUILDDIR" libclang
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install-libclang \
		install-clang-headers
	find "$PKGDEST/usr/include" -mindepth 1 -maxdepth 1 \
		! -name clang-c -exec rm -rf -- {} + 2>/dev/null || true
	install -D -m 0644 "$SRC/clang/LICENSE.TXT" \
		"$PKGDEST/usr/share/licenses/libclang/LICENSE.TXT"
	# Proven v0 leak check: no build paths may survive in ELF metadata.
	find "$PKGDEST" -type f -print | while IFS= read -r file; do
		if readelf -d "$file" 2>/dev/null |
			grep -Eq '(RPATH|RUNPATH).*(/var/tmp|/mnt/akadata|/out/rootfs|/out/sysroot|/build)'; then
			printf 'libclang: build path leaked into %s\n' "$file" >&2
			exit 1
		fi
	done
}

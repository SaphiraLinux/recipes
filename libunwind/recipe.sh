#!/bin/sh

pkgname=libunwind
pkgver=22.1.8
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="LLVM libunwind: unwinding runtime providing _Unwind_* and .eh_frame based stack unwinding"
license="Apache-2.0 WITH LLVM-exception"
origin=libunwind
repo=saphira
url=https://llvm.org/
source=https://github.com/llvm/llvm-project/releases/download/llvmorg-22.1.8/llvm-project-22.1.8.src.tar.xz
sha256=922f1817a0df7b1489272d18134ee0087a8b068828f87ac63b9861b1a9965888

makedepends="
    binutils
    cmake
    gcc
    ninja
    python3
"

subpackages="libunwind-dev"

# Native adaptation of the proven v0 recipe: gcc instead of clang (no
# clang in the native universe), so compiler-rt builtins are not used
# and the Saphira musl target triple flags are dropped. Rust std on
# musl links -lunwind, so the static library is installed (v0 flag
# preserved).
recipe_build()
{
	cmake -G Ninja "$SRC/runtimes" -B "$BUILDDIR" \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_SKIP_RPATH=ON \
		-DCMAKE_C_FLAGS="${CFLAGS-}" \
		-DCMAKE_CXX_FLAGS="${CXXFLAGS-}" \
		-DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS-}" \
		-DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS-}" \
		-DLLVM_ENABLE_RUNTIMES=libunwind \
		-DLIBUNWIND_INCLUDE_TESTS=OFF \
		-DLIBUNWIND_INCLUDE_DOCS=OFF \
		-DLIBUNWIND_ENABLE_ASSERTIONS=OFF \
		-DLIBUNWIND_USE_COMPILER_RT=OFF \
		-DLIBUNWIND_INSTALL_STATIC_LIBRARY=ON \
		-DLIBUNWIND_INSTALL_SHARED_LIBRARY=ON
	ninja -C "$BUILDDIR" unwind
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install-unwind
	install -D -m 0644 "$SRC/libunwind/LICENSE.TXT" \
		"$PKGDEST/usr/share/licenses/libunwind/LICENSE.TXT"
}

#!/bin/sh

pkgname=compiler-rt
pkgver=22.1.8
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="LLVM compiler runtime: builtins, sanitizers and profiler runtime libraries"
license="Apache-2.0 WITH LLVM-exception"
origin=compiler-rt
repo=saphira
url=https://compiler-rt.llvm.org/
source=https://github.com/llvm/llvm-project/releases/download/llvmorg-22.1.8/llvm-project-22.1.8.src.tar.xz
sha256=922f1817a0df7b1489272d18134ee0087a8b068828f87ac63b9861b1a9965888

makedepends="
    binutils
    clang>=22.1.8-r1
    cmake
    llvm>=22.1.8-r1
    make
    ninja
    python3
"

# Proven v0 approach: compiler-rt is built by the native clang itself
# with the Saphira musl target, installing into the Clang 22 resource
# directory. GWP-ASan, libFuzzer and tests are off as in v0.
recipe_build()
{
	cmake -G Ninja "$SRC/compiler-rt" -B "$BUILDDIR" \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_SKIP_RPATH=ON \
		-DCMAKE_C_COMPILER=clang \
		-DCMAKE_CXX_COMPILER=clang++ \
		-DCMAKE_ASM_COMPILER=clang \
		-DCMAKE_C_COMPILER_TARGET=x86_64-akadata-linux-musl \
		-DCMAKE_CXX_COMPILER_TARGET=x86_64-akadata-linux-musl \
		-DCMAKE_ASM_COMPILER_TARGET=x86_64-akadata-linux-musl \
		-DCMAKE_C_FLAGS="${CFLAGS-}" \
		-DCMAKE_CXX_FLAGS="${CXXFLAGS-}" \
		-DCMAKE_EXE_LINKER_FLAGS="${LDFLAGS-}" \
		-DCMAKE_SHARED_LINKER_FLAGS="${LDFLAGS-}" \
		-DLLVM_CONFIG_PATH=/usr/bin/llvm-config \
		-DCOMPILER_RT_INSTALL_PATH=/usr/lib/clang/22 \
		-DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
		-DCOMPILER_RT_BUILD_GWP_ASAN=OFF \
		-DCOMPILER_RT_INCLUDE_TESTS=OFF \
		-DCOMPILER_RT_BUILD_LIBFUZZER=OFF
	ninja -C "$BUILDDIR"
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install
	test -d "$PKGDEST/usr/lib/clang/22/lib/linux" ||
		{ printf 'compiler-rt: missed the Clang 22 resource directory\n' >&2; exit 1; }
	install -D -m 0644 "$SRC/compiler-rt/LICENSE.TXT" \
		"$PKGDEST/usr/share/licenses/compiler-rt/LICENSE.TXT"
}

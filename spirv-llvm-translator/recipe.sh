#!/bin/sh

pkgname=spirv-llvm-translator
pkgver=22.1.7
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="SPIRV-LLVM translator library (Mesa OpenCL/NVK build requirement)"
license='Apache-2.0'
origin=spirv-llvm-translator
repo=saphira
url=https://github.com/KhronosGroup/SPIRV-LLVM-Translator
source=https://github.com/KhronosGroup/SPIRV-LLVM-Translator/archive/refs/tags/v22.1.7.tar.gz
sha256=2b46118831851f1d43eaf20f05ae9cec4088a666e169d9fe4762b9b21826842b

depends="
    gcc-libs
    llvm
"

makedepends="
    binutils
    cmake
    gcc
    make
    ninja
    pkgconf
    python3
    llvm
    spirv-headers
"

# Version-locked to the native LLVM (22.1.x satisfies mesa's
# >=22.1,<22.2 requirement). Static archive ships for the
# -Bstatic rust link style consumers; shared object for normal
# linking. No -dev split (libpng idiom); the CMake package files
# travel with the headers in the main package.
# SPIRV-Headers come from the native spirv-headers package (pinned to
# this translator's spirv-headers-tag.conf companion commit).
# Reconstructing the expected source layout (<dir>/include) from the
# installed headers keeps CMake off its git-clone FetchContent path:
# the clean build root has no git and must not fetch at build time.
recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	mkdir -p spirv-headers-src/include
	cp -r /usr/include/spirv spirv-headers-src/include/
	cmake -G Ninja "$SRC" \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_BUILD_TYPE=Release \
		-DBUILD_SHARED_LIBS=ON \
		-DLLVM_DIR=/usr/lib/cmake/llvm \
		-DLLVM_EXTERNAL_SPIRV_HEADERS_SOURCE_DIR="$BUILDDIR/spirv-headers-src"
	ninja
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install
	for p in \
		usr/lib/pkgconfig/LLVMSPIRVLib.pc \
		usr/include/LLVMSPIRVLib/LLVMSPIRVLib.h \
	; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: spirv-llvm-translator payload is missing $p" >&2
			return 1
		}
	done
}

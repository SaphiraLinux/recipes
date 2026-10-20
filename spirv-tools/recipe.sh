#!/bin/sh

pkgname=spirv-tools
pkgver=2026.3
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Khronos SPIR-V tools and libraries (mesa CLC/NVK requirement)"
license='Apache-2.0'
origin=spirv-tools
repo=saphira
url=https://github.com/KhronosGroup/SPIRV-Tools
vendor=https://github.com/KhronosGroup/SPIRV-Tools/archive/refs/tags/v2026.3.tar.gz
sha256=fff0667b25dfb98177da3cc4cc61ac277d076786df42baaf8d9635a25bdf9226

depends="
    gcc-libs
"

makedepends="
    binutils
    cmake
    gcc
    make
    ninja
    pkgconf
    python3
    spirv-headers
"

# SPIRV-Headers come from the native spirv-headers package (same era:
# v2026.3 tools against 2026-07-02 headers; grammar tables generate at
# build time from the installed JSON). Reconstructing the expected
# source layout (<dir>/include) keeps CMake off its
# external/spirv-headers checkout path: the clean build root has no
# git and must not fetch at build time.
# Tests are OFF (they need googletest/effcee/re2, none packaged);
# -Werror is OFF via the project's own knob: GCC 16's
# -Warray-bounds fires on timer.h inlining analysis (false
# positive, upstream issue class). The assembler/disassembler tools ship, so gcc-libs stays a runtime
# dependency (C++ executables, same idiom as spirv-llvm-translator).
recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	mkdir -p sh-headers/include
	cp -r /usr/include/spirv sh-headers/include/
	[ -f sh-headers/include/spirv/unified1/spirv.core.grammar.json ] || {
		echo "ERROR: spirv-tools needs installed SPIR-V grammar JSON" >&2
		return 1
	}
	cmake -G Ninja "$SRC" \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DCMAKE_BUILD_TYPE=Release \
		-DSPIRV-Headers_SOURCE_DIR="$BUILDDIR/sh-headers" \
		-DSPIRV_SKIP_TESTS=ON \
		-DSPIRV_WERROR=OFF
	ninja
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install
	for p in \
		usr/lib/pkgconfig/SPIRV-Tools.pc \
		usr/include/spirv-tools/libspirv.hpp \
		usr/bin/spirv-as \
	; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: spirv-tools payload is missing $p" >&2
			return 1
		}
	done
}

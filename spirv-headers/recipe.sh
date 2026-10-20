#!/bin/sh

pkgname=spirv-headers
pkgver=20260708
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Khronos SPIR-V headers (companion to spirv-llvm-translator)"
license='MIT'
origin=spirv-headers
repo=saphira
url=https://github.com/KhronosGroup/SPIRV-Headers
vendor=https://github.com/KhronosGroup/SPIRV-Headers/archive/29981f65241605e08b0ede4cfeb999fe3b723c6a.tar.gz
sha256=232899f1ad4104fb5bc377b94596c7621575eee62ad9a9e8f929b63a7dd8a7ad

depends=""

makedepends=""

# Pinned to the exact commit named by SPIRV-Tools v2026.3's DEPS
# (2026-07-08). spirv-llvm-translator 22.1.7's tag-conf names an older
# commit (2026-07-02); the translator tolerates newer headers (it
# consumes only core spirv.hpp, backward compatible), while the tools
# require their DEPS pin (newer enums such as MultipleWaitQueuesQCOM).
# If either consumer is bumped, re-check both pins here.
# Headers-only payload: the translator consumes them as a source-layout
# directory (<dir>/include), reconstructed at its build time from
# /usr/include, so the translator's CMake never reaches its git-clone
# FetchContent path (no git in the clean build root).
recipe_build()
{
	[ -d "$SRC/include/spirv" ] || {
		echo "ERROR: spirv-headers archive has no include/spirv tree" >&2
		return 1
	}
}

recipe_install()
{
	mkdir -p "$PKGDEST/usr/include"
	cp -r "$SRC/include/." "$PKGDEST/usr/include/"
	[ -d "$PKGDEST/usr/include/spirv" ] || {
		echo "ERROR: spirv-headers payload is missing usr/include/spirv" >&2
		return 1
	}
}

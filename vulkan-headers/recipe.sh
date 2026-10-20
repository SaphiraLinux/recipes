#!/bin/sh
pkgname=vulkan-headers
pkgver=1.4.363.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Vulkan API headers and registry (header-only, for mesa Vulkan drivers)'
license='Apache-2.0'
origin=vulkan-headers
repo=saphira
url=https://github.com/KhronosGroup/Vulkan-Headers
source=https://github.com/KhronosGroup/Vulkan-Headers/archive/refs/tags/vulkan-sdk-1.4.363.0.tar.gz
sha256=4a078be12bef21cfebc09d878b77a63cff9d68f899254a0b00d0e37ef73e7f7e

# Header-only: no subpackages (headers ship in main, saphira-linux-uapi-headers
# precedent). Mesa Vulkan drivers (swrast/intel/nouveau/mobile) need these;
# the Vulkan loader itself is a separate follow-up (see rutabaga task).
depends=""
makedepends="
	binutils
	cmake
	gcc
	make
	ninja
"

recipe_build()
{
	cmake -S "$SRC" -B "$BUILDDIR" \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/usr
	cmake --build "$BUILDDIR" -j${JOBS:-$(nproc)}
}

recipe_install()
{
	DESTDIR="$PKGDEST" cmake --install "$BUILDDIR"
}

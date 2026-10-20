#!/bin/sh

pkgname=glslang
pkgver=16.6.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Khronos reference front end for GLSL/ESSL and SPIR-V generator (mesa build-time validator)'
license='BSD-3-Clause'
origin=glslang
repo=saphira
url=https://github.com/KhronosGroup/glslang
# Vendored: https://github.com/KhronosGroup/glslang/archive/refs/tags/16.6.0.tar.gz
vendor=https://github.com/KhronosGroup/glslang/archive/refs/tags/16.6.0.tar.gz
sha256=9c09b901149c729df745057dafa815278aaa101b84d2b6e14f16a42de52f97f2

depends=""

makedepends="
	binutils
	cmake
	gcc
	make
	ninja
"

subpackages="$pkgname-dev"

recipe_build()
{
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/16.6.0.tar.gz"
	cd "$SRC"
	echo "$sha256  $RECIPE_DIR/files/16.6.0.tar.gz" | sha256sum -c -
	cmake -S "$SRC" -B "$BUILDDIR" \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DENABLE_OPT=OFF \
		-DENABLE_GLSLANG_BINARIES=ON \
		-DGLSLANG_TESTS=OFF
	cmake --build "$BUILDDIR" -j${JOBS:-$(nproc)}
}

recipe_install()
{
	DESTDIR="$PKGDEST" cmake --install "$BUILDDIR"
	# ENABLE_OPT=OFF: SPIRV-Tools/SPIRV-Headers are not in the native
	# universe (glslang -> BLOCKED_BY_spirv-tools for the optimizer).
	# Mesa needs only the validator binary at build time, which is
	# unaffected. Re-enable OPT when spirv-tools is ported.
	# GLSLANG_TESTS=OFF: no googletest vendored; release checks live
	# in saphira-packager/tests, never in package payloads.
	# Static libraries are the upstream default; binaries link them in.
	# No /bin|/sbin consumer links the libraries, so /usr/lib (via
	# CMAKE_INSTALL_LIBDIR=lib) is correct under non-usrmerged FHS.
}

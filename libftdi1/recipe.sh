#!/bin/sh
pkgname=libftdi1
pkgver=1.5
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='FTDI USB serial/MPSSE access library plus ftdi_eeprom tool'
license='LGPL-2.0-only GPL-2.0-only'
origin=libftdi1
repo=saphira
url=https://www.intra2net.com/en/developer/libftdi/
source=https://www.intra2net.com/en/developer/libftdi/download/libftdi1-1.5.tar.bz2
sha256=7c7091e9c86196148bd41177b4590dccb1510bfe6cea5bf7407ff194482eb049

# ftdi_eeprom links libconfuse (new Saphira package); the shared C
# library needs libusb at runtime.
depends="libconfuse libusb"
# FTDIPP off: C++ bindings need boost (not justified for flashrom's C
# use). PYTHON_BINDINGS off: swig stack out of scope. EXAMPLES off:
# demo programs, not shipped. DOCUMENTATION off: no doxygen in tree.
# BUILD_TESTS off: needs the Boost unit-test framework.
# CMAKE_INSTALL_LIBDIR alone is ignored upstream (paths use lib${LIB_SUFFIX},
# defaulting to 64); LIB_SUFFIX="" forces /usr/lib (makepkg refuses lib64).
# CMAKE_POLICY_VERSION_MINIMUM=3.5: upstream still declares
# cmake_minimum_required < 3.5, removed in CMake 4 (jansson/yajl precedent).
makedepends="binutils cmake gcc libconfuse-dev libusb-dev make pkgconf"
subpackages="$pkgname-dev"

recipe_build() {
	FTDI_BALL="$RECIPE_DIR/files/libftdi1-${pkgver}.tar.bz2"
	echo "$sha256  $FTDI_BALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$FTDI_BALL"
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	cmake "$SRC" \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DLIB_SUFFIX="" \
		-DCMAKE_BUILD_TYPE=Release \
		-DBUILD_SHARED_LIBS=ON \
		-DSTATICLIBS=OFF \
		-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
		-DFTDIPP=OFF \
		-DFTDI_EEPROM=ON \
		-DEXAMPLES=OFF \
		-DDOCUMENTATION=OFF \
		-DBUILD_TESTS=OFF \
		-DPYTHON_BINDINGS=OFF
	make -j${JOBS:-$(nproc)}
}

recipe_install() {
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
}

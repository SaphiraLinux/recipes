#!/bin/sh

pkgname=dcmtk
pkgver=3.7.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='DICOM ToolKit: command-line tools (echoscu, echoscp, storescu, ...) and libraries'
license='BSD-3-Clause OR MIT OR libtiff'
origin=dcmtk
repo=saphira
url=https://dicom.offis.de/en/dcmtk/
source=https://dicom.offis.de/download/dcmtk/dcmtk370/dcmtk-${pkgver}.tar.gz
sha256=f103df876040a4f904f01d2464f7868b4feb659d8cd3f46a5f1f61aa440be415

depends="openssl zlib"
makedepends="
	cmake
	gcc
	make
	openssl-dev
	zlib-dev
"

subpackages="$pkgname-dev"

# All DCMTK tools are CLI; no GUI toolkit is ever enabled (GUI would
# require WX which stays off by default). Optional image/XML codecs are
# disabled: echoscu/echoscp/storescu and friends are network tools and
# do not need libpng/libtiff/libjpeg/libxml2, keeping the closure lean.
recipe_build()
{
	cmake -S "$SRC" -B "$BUILDDIR" \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DBUILD_SHARED_LIBS=ON \
		-DDCMTK_WITH_OPENSSL=ON \
		-DDCMTK_WITH_ZLIB=ON \
		-DDCMTK_WITH_PNG=OFF \
		-DDCMTK_WITH_TIFF=OFF \
		-DDCMTK_WITH_LIBJPEG=OFF \
		-DDCMTK_WITH_XML=OFF \
		-DDCMTK_WITH_DOXYGEN=OFF
	cmake --build "$BUILDDIR" -j${JOBS:-$(nproc)}

	# Network-tool validation: version banners of the exact tools used
	# for loadbalancer health checks. NOTE: DCMTK 3.7.0 removed echoscp
	# (echoscu handles both SCU and SCP roles since 3.6.9).
	"$BUILDDIR"/bin/echoscu --version | grep -qi echoscu
	"$BUILDDIR"/bin/storescu --version | grep -qi storescu
	"$BUILDDIR"/bin/storescp --version | grep -qi storescp
}

recipe_install()
{
	DESTDIR="$PKGDEST" cmake --install "$BUILDDIR"
	find "$PKGDEST" -name '*.la' -delete
	test -x "$PKGDEST/usr/bin/echoscu"
	test -x "$PKGDEST/usr/bin/storescu"
}

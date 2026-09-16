#!/bin/sh

# CMU PocketSphinx 5.1.1: lightweight speech recognition.
#
# The recognition half of the console stack (voices are edge-tts
# cloud-side, espeak-ng local): offline command-word spotting and
# batch transcription with the in-tree en-us acoustic model, no
# network and no GPU. C library plus CLI tools; the Python
# (cython) bindings stay out - consumers here link the C API.
#
# Tag archive (no source assets attached to the release):
# self-contained, no submodules, no FetchContent. GStreamer
# plugin stays off (no gst in the tree); fixed-point stays off
# (server CPUs have real FPUs).

pkgname=pocketsphinx
pkgver=5.1.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="CMU lightweight speech recognition engine and tools"
license=BSD-2-Clause
origin=pocketsphinx
repo=saphira
url=https://cmusphinx.github.io/
source=https://github.com/cmusphinx/pocketsphinx/archive/refs/tags/v5.1.1.tar.gz
sha256=e2db414eb66618cd0a98de77507db32517a48f6900b06bfb94c0acc4bef5761d

depends="
    musl
"
makedepends="
    binutils
    cmake
    gcc
    make
    pkgconf
"
subpackages="$pkgname-dev"

recipe_build()
{
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/v5.1.1.tar.gz"
	echo "$sha256  $RECIPE_DIR/files/v5.1.1.tar.gz" | sha256sum -c -
	cd "$SRC"
	test -d model/en-us ||
		{ echo "ERROR: in-tree en-us model missing" >&2; return 1; }
	cmake -B build -S . -DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DBUILD_SHARED_LIBS=ON \
		-DCMAKE_BUILD_TYPE=Release
	cmake --build build -j${JOBS:-$(nproc)}
}

recipe_install()
{
	DESTDIR="$PKGDEST" cmake --install "$SRC/build"
	test -f "$PKGDEST/usr/lib/libpocketsphinx.so" ||
		{ echo "ERROR: libpocketsphinx.so missing from payload" >&2; return 1; }
	test -x "$PKGDEST/usr/bin/pocketsphinx_batch" ||
		{ echo "ERROR: pocketsphinx_batch missing from payload" >&2; return 1; }
	test -d "$PKGDEST/usr/share/pocketsphinx/model/en-us" ||
		{ echo "ERROR: en-us model missing from payload" >&2; return 1; }
}

#!/bin/sh
# whisper.cpp: high-performance Whisper ASR inference (STT leg of the
# optional Saphira PBX local speech subsystem). CPU-only build; ggml
# ships vendored inside the upstream release tarball (verified: the
# ggml/ tree is present, no submodule fetch at build time). Models
# are data, never vendored here: fetch a small English model at
# provision/test time and point the speech service at it via an
# explicit model path (see saphira-pbx speech docs).
pkgname=whisper-cpp
pkgver=1.9.5
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Whisper speech recognition (local STT engine)'
license='MIT'
origin=whisper-cpp
repo=saphira
url=https://github.com/ggml-org/whisper.cpp
source=https://github.com/ggml-org/whisper.cpp/archive/refs/tags/v1.9.5.tar.gz
sha256=ff1a9053feb509ff9d7729703355541ae9690073a6b1c40eb692c962e0dc1720

# Static libraries only: bitnet-cpp already owns the shared
# libggml.so path (different ggml generation, incompatible), and a
# leaf STT engine has no business fighting over it. whisper-cli
# links statically; -dev carries archives + headers, no .so files.
# C++ consumers need gcc-libs at runtime (never the full compiler).
depends="gcc-libs"
makedepends="binutils cmake gcc make"
subpackages="$pkgname-dev"

recipe_build() {
	WHISPER_BALL="$RECIPE_DIR/files/v1.9.5.tar.gz"
	echo "$sha256  $WHISPER_BALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$WHISPER_BALL"
	# whisper-cli (transcribe files) is the production entry point;
	# server/extra examples stay out. No GPU backends on Saphira.
	cmake -S "$SRC" -B "$BUILDDIR" \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DBUILD_SHARED_LIBS=OFF \
		-DWHISPER_BUILD_TESTS=OFF \
		-DWHISPER_BUILD_SERVER=OFF \
		-DWHISPER_BUILD_EXAMPLES=ON \
		-DWHISPER_CURL=OFF \
		-DWHISPER_SDL2=OFF \
		-DWHISPER_FFMPEG=OFF
	cmake --build "$BUILDDIR" -j${JOBS:-$(nproc)}
}
recipe_install() {
	DESTDIR="$PKGDEST" cmake --install "$BUILDDIR"
	[ -x "$PKGDEST/usr/bin/whisper-cli" ] || \
		{ echo "ERROR: whisper-cli missing from payload" >&2; return 1; }
}

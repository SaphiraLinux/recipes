#!/bin/sh
pkgname=pahole
pkgver=1.31
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Pahole and other DWARF2 utilities (BTF conversion)'
license='GPL-2.0-only'
origin=pahole
repo=saphira
url=https://git.kernel.org/pub/scm/devel/pahole/pahole.git
pahole_sha256=0a7f255ccacf8cc7f8cd119099eb327179b4b3c67cb015af646af6d0cb03054d
depends="elfutils gcc-libs musl-obstack argp-standalone musl-fts"
makedepends="elfutils-dev musl-obstack-dev argp-standalone-dev musl-fts-dev cmake gcc make pkgconf zlib-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/pahole-1.31.tar.xz"
	cd "$SRC"
	echo "$pahole_sha256  $RECIPE_DIR/files/pahole-1.31.tar.xz" | sha256sum -c -
	cmake -B build -DCMAKE_INSTALL_PREFIX=/usr \
		-D__LIB=lib -DLIBDIR=lib -DCMAKE_INSTALL_LIBDIR=lib \
		-DENABLE_BPF=OFF -DCMAKE_EXE_LINKER_FLAGS="-largp -lfts" -DCMAKE_C_FLAGS="-I/usr/include -Wno-error=unused-but-set-variable -Wno-error=incompatible-pointer-types"
	cmake --build build -j${JOBS:-$(nproc)}
}
recipe_install() {
	DESTDIR="$PKGDEST" cmake --install "$SRC/build"
	# Saphira /lib-only policy: cmake may stage lib64 despite INSTALL_LIBDIR
	if [ -d "$PKGDEST/usr/lib64" ]; then
		cp -a "$PKGDEST/usr/lib64/." "$PKGDEST/usr/lib/"
		rm -rf "$PKGDEST/usr/lib64"
	fi
}

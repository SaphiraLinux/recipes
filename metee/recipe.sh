#!/bin/sh
pkgname=metee
pkgver=6.2.6
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Intel ME TEE client library (CSE/CSME/GSC access over MEI)'
license='Apache-2.0'
origin=metee
repo=saphira
url=https://github.com/intel/metee
source=https://github.com/intel/metee/archive/refs/tags/${pkgver}.tar.gz
sha256=adb5e2b4f3129616b7d3b095c8838a2041dc5240bfbdc67cd02aeeae807defc9

# Shared library only (upstream defaults to static). The .pc file is
# Saphira-authored -dev metadata (upstream ships none); version and
# paths match this package. VTAG ioctl probing uses kernel headers.
# -Wno-error=sign-conversion: upstream builds -Werror and probes this
# warning on; gcc 16 then rejects the three standard ioctl() calls whose
# _IOC request codes are unsigned by kernel design (musl takes int).
# Surgical downgrade only (nginx/pahole precedent), never blanket.
depends=""
makedepends="binutils cmake gcc make pkgconf saphira-kernel-headers"
subpackages="$pkgname-dev"

recipe_build() {
	METEE_BALL="$RECIPE_DIR/files/${pkgver}.tar.gz"
	echo "$sha256  $METEE_BALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$METEE_BALL"
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	cmake "$SRC" \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_C_FLAGS="-Wno-error=sign-conversion" \
		-DBUILD_SHARED_LIBS=ON \
		-DBUILD_DOCS=OFF \
		-DBUILD_TEST=OFF \
		-DBUILD_SAMPLES=OFF
	make -j${JOBS:-$(nproc)}
}

recipe_install() {
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
	sed "s/^Version:.*/Version: ${pkgver}/" \
		"$RECIPE_DIR/files/metee.pc" > "$BUILDDIR/metee.pc"
	install -D -m 0644 "$BUILDDIR/metee.pc" \
		"$PKGDEST/usr/lib/pkgconfig/metee.pc"
}

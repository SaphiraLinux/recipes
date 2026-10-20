#!/bin/sh
pkgname=xz
pkgver=5.8.3
# r4: FHS non-usrmerged — /bin/kmod + /sbin/depmod family link
# liblzma, so the runtime SONAME chain ships in /lib (verified
# 2026-10-19 via ldd). Dev linker name stays in /usr/lib (acl/zstd
# precedent). Egg carries unowned 5.8.1 stage1 fossils in /lib;
# the package must stage the 5.8.3 runtime in /lib.
pkgrel=4
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='XZ compression library and tools'
license='0BSD AND GPL-2.0-or-later AND LGPL-2.1-or-later'
origin=xz
repo=saphira
url=https://tukaani.org/xz/
xz_sha256=fff1ffcf2b0da84d308a14de513a1aa23d4e9aa3464d17e64b9714bfdd0bbfb6
depends=""
makedepends="gawk gcc make"
subpackages="$pkgname-dev"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/xz-5.8.3.tar.xz"
	cd "$SRC"
	echo "$xz_sha256  $RECIPE_DIR/files/xz-5.8.3.tar.xz" | sha256sum -c -
	./configure --prefix=/usr --sysconfdir=/etc --disable-scripts --disable-nls --localstatedir=/var
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
	find "$PKGDEST" -name '*.la' -delete
	# FHS non-usrmerged: /bin|/sbin consumers (kmod, depmod family)
	# need the runtime SONAME chain in /lib. The /usr/lib/liblzma.so
	# linker name is a development artefact, not usrmerge: it points
	# at the absolute /lib target. No relative ../ cross-tree links.
	mkdir -p "$PKGDEST/lib"
	for lib in "$PKGDEST/usr/lib/liblzma.so.5"*; do
		[ -e "$lib" ] && mv "$lib" "$PKGDEST/lib/"
	done
	ln -sf /lib/liblzma.so.5 "$PKGDEST/usr/lib/liblzma.so"
	# Stage1-leak guard (2026-10-19 file fossil incident): a clean
	# native build must never embed /saphirabuild stage paths.
	if grep -rqF '/saphirabuild/' "$PKGDEST"; then
		echo "ERROR: staged payload leaks /saphirabuild stage path" >&2
		return 1
	fi
}

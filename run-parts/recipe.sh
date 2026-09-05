pkgname=run-parts
pkgver=5.23.2
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Run scripts in a directory (run-parts from debianutils)'
license='GPL-2.0-or-later'
origin=run-parts
repo=main
url=https://salsa.debian.org/debian/debianutils
# Vendored upstream tarball, bytes pinned:
# http://deb.debian.org/debian/pool/main/d/debianutils/debianutils_5.23.2.tar.xz
run_parts_sha256=79e524b7526dba2ec5c409d0ee52ebec135815cf5b2907375d444122e0594b69

depends=""
makedepends="gcc make"

recipe_build() {
	tar --no-same-owner -C "$SRC" -xf "$RECIPE_DIR/files/debianutils-5.23.2.tar.xz"
	echo "$run_parts_sha256  $RECIPE_DIR/files/debianutils-5.23.2.tar.xz" | sha256sum -c -
	# Single-file build exactly as the reference recipe: the work/
	# tree of debianutils carries run-parts.c and its man page.
	cc ${CPPFLAGS-} ${CFLAGS--O2} -DHAVE_GETOPT_H \
		-DPACKAGE_VERSION='"5.23.2"' \
		${LDFLAGS-} -o "$BUILDDIR/run-parts" "$SRC/work/run-parts.c"
}

recipe_install() {
	install -D -m 0755 "$BUILDDIR/run-parts" "$PKGDEST/usr/bin/run-parts"
	install -D -m 0644 "$SRC/work/run-parts.8" \
		"$PKGDEST/usr/share/man/man8/run-parts.8"
}

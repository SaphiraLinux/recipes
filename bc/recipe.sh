pkgname=bc
pkgver=7.0.0
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='GNU bc arbitrary-precision calculator language (kbuild timeconst dependency)'
license='GPL-3.0-or-later'
origin=bc
repo=main
url=https://github.com/gavinhoward/bc
# Vendored: https://github.com/gavinhoward/bc/releases/download/7.0.0/bc-7.0.0.tar.gz
bc_sha256=ea99f18482c2fd3775f1b6de4b2faf6dd2eed9e8e6699c0d4ecf54b539affd43

makedepends="
	binutils
	gawk
	gcc
	make
"

recipe_build()
{
	BCBALL="$RECIPE_DIR/files/bc-7.0.0.tar.gz"
	echo "$bc_sha256  $BCBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$BCBALL"
	cd "$SRC"
	export CC=gcc
	./configure.sh --prefix /usr
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}

pkgname=iniparser
pkgver=4.3.2
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Standalone ini file parser (ndctl test tooling dependency)'
license=MIT
origin=iniparser
repo=main
url=https://github.com/ndevilla/iniparser
# codeload snapshot tarball (upstream publishes no release assets);
# basename is the tag, pinned by sha256 like any other vendor archive.
vendor=https://codeload.github.com/ndevilla/iniparser/tar.gz/refs/tags/v4.3.2
sha256=e9eb6be555c30fbef87e5a07333fcff6ef8c5bbbdc5710321bbad7ebae0612a7

subpackages="$pkgname-dev"
makedepends="
	binutils
	cmake
	gcc
	make
"

recipe_build()
{
	cmake -B build -S . -DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_LIBDIR=lib \
		-DBUILD_SHARED_LIBS=ON
	cmake --build build -j${JOBS:-$(nproc)}
}

recipe_install()
{
	DESTDIR="$PKGDEST" cmake --install build
}

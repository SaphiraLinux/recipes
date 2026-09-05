pkgname=json-c
pkgver=0.19
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='JSON library in C (libvirt QEMU driver dependency)'
license=MIT
origin=json-c
repo=main
source=https://github.com/json-c/json-c/releases/download/json-c-0.19-20260627/json-c-0.19.tar.gz
url=https://github.com/json-c/json-c
# Vendored: https://github.com/json-c/json-c/archive/refs/tags/json-c-0.19.tar.gz
sha256=37ad0249902e301bd9052bf712e511fcc6acff4ecaad4b5900aad9ce564e26de

subpackages="$pkgname-dev"
makedepends="
	binutils
	cmake
	gcc
	make
	pkgconf
"

recipe_build()
{
	cmake -B build -S . -DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_LIBDIR=lib -DBUILD_STATIC_LIBS=OFF -DDISABLE_WERROR=ON
	cmake --build build -j${JOBS:-$(nproc)}
}

recipe_install()
{
	DESTDIR="$PKGDEST" cmake --install build
}

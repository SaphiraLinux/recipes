pkgname=libbpf
pkgver=1.7.0
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='eBPF CO-RE library (bpf object loading, program/map management)'
license='LGPL-2.1-or-later BSD-2-Clause'
origin=libbpf
repo=main
url=https://github.com/libbpf/libbpf
source=https://github.com/libbpf/libbpf/archive/refs/tags/v${pkgver}.tar.gz
sha256=7ab5feffbf78557f626f2e3e3204788528394494715a30fc2070fcddc2051b7b

depends="elfutils zlib"
makedepends="elfutils-dev gcc make pkgconf saphira-kernel-headers=7.1.5 zlib-dev"
subpackages="$pkgname-dev"

recipe_build() {
	make -C "$SRC/src" -j${JOBS:-$(nproc)}
}

recipe_install() {
	make -C "$SRC/src" DESTDIR="$PKGDEST" \
		PREFIX=/usr LIBDIR=/usr/lib \
		install install_headers
	install -D -m 0644 "$SRC/LICENSE" \
		"$PKGDEST/usr/share/licenses/libbpf/LICENSE"
}

#!/bin/sh

pkgname=pciutils
pkgver=3.15.0
# r2: no upstream change; produce the pciutils-dev split (libpci
# headers) that flashrom's internal/PCI programmers need. The r1 build
# predates the split, so only the main package reached the repository.
# r3: run upstream install-lib so headers, .pc and the .so link actually
# land in the payload (plain install ships none of them; the -dev split
# came out empty at r2).
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='PCI bus utilities (lspci, setpci) - device names and vid:pid via pci.ids'
license='GPL-2.0-or-later'
origin=pciutils
repo=saphira
url=https://mj.ucw.cz/sw/pciutils/
# Vendored: https://github.com/pciutils/pciutils/archive/refs/tags/v3.15.0.tar.gz
pciutils_sha256=06f467642057599acf396bc17340452fac3308f1e08be19e0c32587e42d7017b

depends="hwdata zlib"
makedepends="
	binutils
	gcc
	saphira-kernel-headers
	make
	pkgconf
	zlib-dev
"

subpackages="$pkgname-dev"

recipe_build()
{
	PCBALL="$RECIPE_DIR/files/pciutils-3.15.0.tar.gz"
	echo "$pciutils_sha256  $PCBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$PCBALL"
	make -C "$SRC" -j${JOBS:-$(nproc)} \
		SHARED=yes ZLIB=yes PCI_COMPRESSED_IDS=0 \
		PREFIX=/usr LIBDIR=/usr/lib \
		IDSDIR=/usr/share/hwdata MANDIR=/usr/share/man \
		CC=gcc
}

recipe_install()
{
	make -C "$SRC" install SHARED=yes ZLIB=yes PCI_COMPRESSED_IDS=0 \
		PREFIX=/usr LIBDIR=/usr/lib \
		IDSDIR=/usr/share/hwdata MANDIR=/usr/share/man \
		DESTDIR="$PKGDEST"
	# install-lib adds the libpci headers, .pc file and .so link that
	# the -dev split is made of (plain install omits all three).
	make -C "$SRC" install-lib SHARED=yes ZLIB=yes PCI_COMPRESSED_IDS=0 \
		PREFIX=/usr LIBDIR=/usr/lib \
		IDSDIR=/usr/share/hwdata MANDIR=/usr/share/man \
		DESTDIR="$PKGDEST"
}

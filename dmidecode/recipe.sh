pkgname=dmidecode
pkgver=3.6
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='DMI/SMBIOS table decoder (host hardware inventory)'
license=GPL-2.0-or-later
origin=dmidecode
repo=saphira
url=https://www.nongnu.org/dmidecode/
# Vendored: https://download.savannah.nongnu.org/releases/dmidecode/dmidecode-3.6.tar.xz
dmidecode_sha256=e40c65f3ec3dafe31ad8349a4ef1a97122d38f65004ed66575e1a8d575dd8bae

makedepends="
	binutils
	gcc
	saphira-kernel-headers=7.1.5
	make
"

recipe_build()
{
	DMBALL="$RECIPE_DIR/files/dmidecode-3.6.tar.xz"
	echo "$dmidecode_sha256  $DMBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$DMBALL"
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" prefix=/usr install
}

pkgname=efibootmgr
pkgver=18
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='EFI boot manager (edit UEFI boot entries from userspace)'
license='GPL-2.0-or-later'
origin=efibootmgr
repo=main
url=https://github.com/rhboot/efibootmgr
source=https://github.com/rhboot/efibootmgr/releases/download/${pkgver}/efibootmgr-${pkgver}.tar.bz2
sha256=2b195f912aa353f0d11f21f207684c91460fbc37f9a4f2673e63e5e32d108b10

depends="efivar popt"
makedepends="efivar-dev gcc make pkgconf popt-dev"

recipe_build() {
	# musl-gettext.patch (worker-applied) stubs the i18n macros for
	# musl (proven akadata decision). EFIDIR groups our boot entries.
	make -C "$SRC" -j${JOBS:-$(nproc)} PCDIR=/usr/lib/pkgconfig EFIDIR=Saphira
}

recipe_install() {
	make -C "$SRC" PCDIR=/usr/lib/pkgconfig EFIDIR=Saphira \
		DESTDIR="$PKGDEST" install
	rm -rf "$PKGDEST/usr/share/man" "$PKGDEST/usr/share/doc" \
		"$PKGDEST/usr/share/info"
}

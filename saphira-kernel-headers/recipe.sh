pkgname=saphira-kernel-headers
pkgver=7.1.5
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Saphira kernel UAPI headers (Genesis SDK base - all toolchain packages build against 7.1.5 until the deliberate whole-world 7.2.2 generation)'
license=GPL-2.0-only
origin=saphira-kernel-headers
repo=main
url=https://saphira.vm2.uk/
# Upstream kernel tarball pinned per pkgver. 7.1.5 hash = Genesis kernel
# tarball (/usr/src/linux-7.1.5.tar.xz); 7.2.2 hash matches saphira-kernel.
# kernel.org signs the uncompressed .tar; verify procedure as saphira-kernel:
# xz -dc file.xz > file.tar && gpg --verify linux-<ver>.tar.sign file.tar
source=https://mirrors.edge.kernel.org/pub/linux/kernel/v7.x/linux-${pkgver}.tar.xz
sha256=22a0196b3cbcdf34dc27b77561f4d040585fd3447edc9ab3531a1ac79e3041e7

depends=""

makedepends="
	gcc
	make
	perl
	rsync
"

recipe_build()
{
	patch -d "$SRC" -Np1 \
		-i "$RECIPE_DIR/files/0003-libc-compat-musl-netinet-in-coordination.patch"
	make -C "$SRC" ARCH=x86_64 mrproper headers
}

recipe_install()
{
	make -C "$SRC" ARCH=x86_64 INSTALL_HDR_PATH="$PKGDEST/usr" headers_install
	rm -f "$PKGDEST/usr/include/Makefile"
	rm -rf "$PKGDEST/usr/include/drm"
}

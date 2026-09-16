pkgname=saphira-kernel-headers
pkgver=${SAPHIRA_KERNEL_VERSION:-7.1.5}
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Saphira kernel UAPI headers (version selected by SAPHIRA_KERNEL_VERSION)'
license=GPL-2.0-only
origin=saphira-kernel-headers
repo=main
url=https://saphira.vm2.uk/
# Upstream kernel tarball per version line (SAPHIRA_KERNEL_VERSION selects;
# same pattern and pins as the saphira-kernel recipe). Default stays 7.1.5
# (Genesis SDK base). kernel.org signs the uncompressed .tar; verify
# procedure as saphira-kernel:
# xz -dc file.xz > file.tar && gpg --verify linux-<ver>.tar.sign file.tar
case "$pkgver" in
	7.1.5)
		vendor=https://mirrors.edge.kernel.org/pub/linux/kernel/v7.x/linux-7.1.5.tar.xz
		sha256=22a0196b3cbcdf34dc27b77561f4d040585fd3447edc9ab3531a1ac79e3041e7
		;;
	7.2.2)
		vendor=https://mirrors.edge.kernel.org/pub/linux/kernel/v7.x/linux-7.2.2.tar.xz
		sha256=7d0e7ce14f98c43efe880cffbf354a59be45928fdf7170d7333c374ae91c0d83
		;;
	7.2.3)
		vendor=https://mirrors.edge.kernel.org/pub/linux/kernel/v7.x/linux-7.2.3.tar.xz
		sha256=8ba259e8e7b13ec6ef0941c8a39ad90b24bd4a4d6c0010ba6bafb794550ecd03
		;;
	7.3-rc1)
		vendor=https://git.kernel.org/torvalds/t/linux-7.3-rc1.tar.gz
		sha256=8d36fbfc7c8906ccfa1ebacc30f84998406504c3f13733a040bb3a3fbe8ac270
		;;
	*) echo "ERROR: no pinned vendor/sha256 for kernel headers $pkgver" >&2; return 1 ;;
esac

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

pkgname=sgdisk
pkgver=1.0.10
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='GPT fdisk: scriptable GPT partition table manipulator (sgdisk)'
license='GPL-2.0-or-later'
origin=sgdisk
repo=saphira
url=https://sourceforge.net/projects/gptfdisk
source=https://downloads.sourceforge.net/project/gptfdisk/gptfdisk/${pkgver}/gptfdisk-${pkgver}.tar.gz
sha256=2abed61bc6d2b9ec498973c0440b8b804b7a72d7144069b5a9209b2ad693a282

depends="popt util-linux"
makedepends="gcc make popt-dev saphira-kernel-headers util-linux-dev"

recipe_build() {
	# sgdisk only: it links libuuid and libpopt. The sibling gdisk and
	# fixparts build from the same objects but are separate tools, and
	# cgdisk needs ncurses, so none of them ship here.
	make -j${JOBS:-$(nproc)} sgdisk
}

recipe_install() {
	# Upstream ships no install target; /usr/sbin matches parted.
	install -D -m0755 sgdisk "$PKGDEST/usr/sbin/sgdisk"
	install -D -m0644 sgdisk.8 "$PKGDEST/usr/share/man/man8/sgdisk.8"
}

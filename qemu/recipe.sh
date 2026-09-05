pkgname=qemu
pkgver=11.1.1
pkgrel=5
pkgarch=${SAPHIRA_ARCH:-x86_64}
	pkgdesc='QEMU x86_64 system emulator (KVM/TCG, VNC+SPICE remote display, USB redirection, slirp)'
license='GPL-2.0-or-later'
origin=qemu
repo=saphira
url=https://www.qemu.org/
# Vendored: https://download.qemu.org/qemu-11.1.1.tar.xz
qemu_sha256=079ffbff8a7111bbc89022107cbabf3bbfd614d5fc9d7cc675991196aca12482

depends="glib libslirp zlib pixman spice-server usbredir libusb libaio"
makedepends="
	binutils
	gawk
	gcc
	glib-dev
	libslirp
	pixman
	pixman-dev
	spice-server
	spice-server-dev
	spice-protocol
	usbredir
	usbredir-dev
	libusb-dev
	openssl-dev
	libaio-dev
	saphira-kernel-headers=7.1.5
	bzip2
	make
	meson
	ninja
	pkgconf
	python3
	zlib-dev
	bzip2
"

# Server build: VNC remote display, no GTK/SDL/OpenGL. x86_64-softmmu
# only. Networking via slirp (user-mode) + tap/bridge from the host side.
recipe_build()
{
	QBALL="$RECIPE_DIR/files/qemu-11.1.1.tar.xz"
	echo "$qemu_sha256  $QBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$QBALL"
	cd "$SRC"
	# r2: VNC enabled for remote management (virt-manager/virt-viewer
	# from homer). GTK/SDL/OpenGL stay off; pixman not required for VNC.
	./configure --prefix=/usr \
		--target-list=x86_64-softmmu \
		--disable-gtk --disable-sdl --disable-opengl --enable-vnc \
		--enable-spice --enable-usb-redir --enable-linux-aio --enable-tpm \
		--enable-pixman --disable-fdt --disable-docs --disable-guest-agent \
		--disable-werror --disable-bochs --disable-cloop \
		--disable-dmg --disable-qcow1 --disable-vdi --disable-vvfat \
		--disable-qed --disable-parallels \
		--enable-slirp \
		--disable-libssh
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}

#!/bin/sh

pkgname=qemu-system-arm
pkgver=11.1.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="QEMU ARM system emulators (aarch64 + arm, TCG; KVM on ARM hosts only)"
license='GPL-2.0-or-later'
origin=qemu-system-arm
repo=saphira
url=https://www.qemu.org/
# Vendored: https://download.qemu.org/qemu-11.1.1.tar.xz
qemu_sha256=079ffbff8a7111bb7cbdf107abf3bbfd614d5fc0a22a8f196aca12482

# PILOT SPLIT, DISABLED: enable only after qemu r8 (full all-targets
# build) proves the shared configure base. See the multi-arch design
# note (openstack MCP, 2026-10-19). Pattern for the family-group
# splits: one recipe per upstream architecture family, building only
# its softmmu targets, shipping only its emulator binaries. Firmware,
# tools, docs and the x86 KVM host family stay solely in qemu main
# (single datadir owner: two packages must never claim
# /usr/share/qemu/*, the ownership gate refuses).
disabled=yes
disabled_reason='pilot split: enable after qemu r8-full validates the shared all-targets configure base'

# Shared runtime closure mirrors qemu main: display, net, block,
# crypto and headless-GPU features are global, not per-arch.
depends="glib libslirp zlib pixman spice-server usbredir libaio dtc libssh bzip2 libjpeg-turbo lzo snappy zstd libpng numactl libseccomp udev curl fuse3 attr gnutls libbpf keyutils mesa libepoxy virglrenderer"

# Same build requirements as qemu main, minus the doc toolchain:
# manpages ship in qemu-doc (built from the full r8 tree), so splits
# carry binaries only.
makedepends="
    binutils
    bison
    flex
    gawk
    gcc
    glib-dev
    libffi-dev
    pcre2-dev
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
    dtc
    dtc-dev
    libssh
    libssh-dev
    saphira-kernel-headers
    bzip2
    bzip2-dev
    make
    meson
    ninja
    pkgconf
    python3
    python3-pip
    setuptools
    wheel
    zlib-dev
    libjpeg-turbo
    libjpeg-turbo-dev
    lzo
    snappy
    zstd
    zstd-dev
    libpng
    numactl
    libseccomp
    libseccomp-dev
    udev
    udev-dev
    curl
    curl-dev
    fuse3
    fuse3-dev
    attr
    attr-dev
    gnutls
    gnutls-dev
    libbpf
    libbpf-dev
    keyutils
    keyutils-dev
    mesa
    mesa-dev
    libglvnd-dev
    libepoxy
    libepoxy-dev
    virglrenderer
    virglrenderer-dev
"

subpackages=""

recipe_build()
{
	QBALL="$RECIPE_DIR/files/qemu-11.1.1.tar.xz"
	echo "$qemu_sha256  $QBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$QBALL"
	cd "$SRC"
	# Same headless-server feature set as qemu main (VNC, no
	# GTK/SDL, EGL-headless + virglrenderer, slirp, TPM, FDT,
	# image-format set, KVM+TCG), restricted to the ARM family
	# targets. KVM accelerates only on ARM hosts; on Saphira
	# x86_64 these emulators run under TCG.
	./configure --prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--target-list=aarch64-softmmu,arm-softmmu \
		--disable-download \
		--enable-system --disable-linux-user --disable-bsd-user \
		--disable-tools --disable-guest-agent \
		--enable-kvm --enable-tcg \
		-Dfdt=system \
		--disable-gtk --disable-sdl --disable-opengl --enable-vnc \
		--enable-opengl \
		--enable-virglrenderer --disable-rutabaga-gfx \
		--disable-sdl-image --disable-vte --disable-dbus-display \
		--enable-spice --enable-usb-redir --enable-linux-aio --enable-tpm \
		--enable-pixman --enable-slirp \
		--enable-bochs --enable-cloop \
		--enable-dmg --enable-qcow1 --enable-vdi --enable-vvfat \
		--enable-qed --enable-parallels \
		--disable-docs --disable-werror \
		--enable-libssh
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	# Binaries only. Firmware, tools, docs and icons stay solely in
	# qemu main (single-owner datadir); this package must install
	# nothing outside usr/bin or it collides at publication.
	for emu in qemu-system-aarch64 qemu-system-arm; do
		install -D -m 0755 "$SRC/build/$emu" \
			"$PKGDEST/usr/bin/$emu"
	done
	# Prove the family: the virt board exists on both emulators
	# (hw/arm/virt.c registers the "virt" alias on the latest
	# versioned machine), the headless GPU path is wired, and no
	# firmware or tool paths leaked into this package.
	for emu in qemu-system-aarch64 qemu-system-arm; do
		[ -x "$PKGDEST/usr/bin/$emu" ] || {
			echo "ERROR: qemu-system-arm staging has no $emu" >&2
			return 1
		}
		"$PKGDEST/usr/bin/$emu" -M help 2>/dev/null | grep -q '^virt' || {
			echo "ERROR: $emu has no virt machine" >&2
			return 1
		}
	done
	"$PKGDEST/usr/bin/qemu-system-aarch64" -display help 2>/dev/null | grep -q egl-headless || {
		echo "ERROR: qemu-system-aarch64 lacks the egl-headless display backend" >&2
		return 1
	}
	[ ! -e "$PKGDEST/usr/share/qemu" ] || {
		echo "ERROR: qemu-system-arm must not ship firmware (qemu main owns the datadir)" >&2
		return 1
	}
	[ ! -e "$PKGDEST/usr/bin/qemu-img" ] || {
		echo "ERROR: qemu-system-arm must not ship tools (qemu main owns them)" >&2
		return 1
	}
}

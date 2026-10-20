pkgname=qemu
pkgver=11.1.1
pkgrel=8
pkgarch=${SAPHIRA_ARCH:-x86_64}
	pkgdesc='QEMU full system emulators (KVM/TCG, FDT, VNC+SPICE remote display, USB redirection, slirp, OpenGL/virgl headless GPU)'
license='GPL-2.0-or-later'
origin=qemu
repo=saphira
url=https://www.qemu.org/
# Vendored: https://download.qemu.org/qemu-11.1.1.tar.xz
qemu_sha256=079ffbff8a7111bbc89022107cbabf3bbfd614d5fc9d7cc675991196aca12482

depends="glib libslirp zlib pixman spice-server usbredir libusb libaio dtc libssh bzip2 libjpeg-turbo lzo snappy zstd libpng numactl libseccomp udev curl fuse3 attr gnutls libbpf keyutils mesa libepoxy virglrenderer"
# pcre2-dev/libffi-dev are direct build inputs, not just runtime
# transitive deps: glib-2.0.pc Requires libpcre2-8 and gobject-2.0.pc
# Requires libffi, so the meson pkg-config probes fail without them
# in the sysroot (proven by qemu r6 configure failure:
# "Package libpcre2-8 was not found"). Same edge libvirt documents.
# bison/flex are QEMU build requirements (hexagon idef-parser
# generators; proven by qemu-user-static failure: "Program 'bison'
# not found"). bzip2-dev/libjpeg-turbo-dev/lzo/snappy/zstd-dev/
# libpng/numactl/libseccomp-dev/udev-dev/curl-dev/fuse3-dev/attr-dev/
# gnutls-dev/libbpf-dev/keyutils-dev switch the matching features from
# silent auto-disable to an explicit, probed enable (report if any
# probe fails instead of silently dropping the capability).
# python3-pip/setuptools/wheel satisfy mkvenv's tooling group from
# system packages so no PyPI download is needed (with
# --disable-download below, PyPI is never contacted).
# mesa/mesa-dev + libepoxy/libepoxy-dev + virglrenderer/
# virglrenderer-dev are the headless GPU stack: EGL surfaceless + GBM
# from the in-tree mesa, GL dispatch from libepoxy, guest virtio-gpu
# rendering from virglrenderer. No X11/Wayland/GTK/SDL anywhere.
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
	saphira-linux-uapi-headers
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
	python-sphinx
	python-sphinx-rtd-theme
	mesa
	mesa-dev
	libepoxy
	libepoxy-dev
	virglrenderer
	virglrenderer-dev
"

subpackages="$pkgname-doc"

# Server build: VNC remote display, no GTK/SDL/OpenGL. All upstream
# system emulators (no --target-list restriction). Networking via slirp
# (user-mode) + tap/bridge from the host side.
# Split ownership (no overlapping paths, builder only supports
# -dev/-doc/-libs subpackages so the splits are separate recipes):
#   qemu                this package: system emulators + tools (qemu-img,
#                       qemu-nbd, qemu-io, qemu-storage-daemon), no
#                       linux-user, no guest agent.
#   qemu-user           dynamic linux-user emulators.
#   qemu-user-static    static linux-user emulators (*-static).
#   qemu-guest-agent    guest-side agent (qemu-ga), never mandatory on
#                       hosts running system emulators.
recipe_build()
{
	QBALL="$RECIPE_DIR/files/qemu-11.1.1.tar.xz"
	echo "$qemu_sha256  $QBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$QBALL"
	cd "$SRC"
	# r7: libssh packaged (0.12.2) so the ssh:// block backend is
	# enabled; docs enabled via Sphinx 9.1.0 + sphinx-rtd-theme 3.1.0
	# (man/HTML in qemu-doc); --disable-download makes the build
	# hermetic (vendored wheels + system packages, PyPI never
	# contacted). Image formats enabled for VM import (bochs/cloop/
	# dmg/qcow1/vdi/vvfat/qed/parallels). KVM + TCG explicit; FDT
	# forced to system libfdt.
	# r8: headless GPU acceleration. The author's headless-rule
	# clarification permits OpenGL/EGL/GBM, virtual GPUs and
	# accelerated headless rendering (the ban is on mandatory
	# graphical desktop dependencies, not on GPU APIs). So:
	# --enable-opengl (EGL-headless display, surfaceless+GBM from the
	# in-tree mesa - no X11/Wayland/GTK/SDL anywhere in the closure)
	# and --enable-virglrenderer (virtio-gpu 3D via the packaged
	# virglrenderer 1.3.0). GPU rendering stays selectable per VM
	# (virtio-vga-gl/virtio-gpu-gl devices, -display egl-headless);
	# CPU-only VMs are unchanged and work on GPU-less machines - no
	# host is forced to have a GPU or a render node.
	# Deliberate disables (documented, not silent):
	# - gtk/sdl/sdl-image/vte/dbus-display: no local display or
	#   desktop integration (RECIPE_RULES.md headless rule as amended:
	#   GPU APIs permitted, desktop stacks stay out; GUI frontends
	#   remain a future optional capability).
	# - rutabaga-gfx: needs a system rutabaga_gfx_ffi (Rust + gfxstream
	#   + cargo vendoring, no QEMU-bundled fallback) - filed as a
	#   separate tracked packaging task, not silently dropped.
	# --enable-seccomp makes QEMU's syscall sandbox fail the build
	# if the libseccomp probe ever breaks, instead of silently
	# dropping the sandbox (libseccomp+dev are already deps; the
	# kernel carries CONFIG_SECCOMP_FILTER, so the sandbox is live
	# on every Saphira host - the flag only hardens the gate).
	# QEMU has no selinux/apparmor options: confinement is libvirt's
	# sVirt side, not the emulator's.
	./configure --prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--disable-download \
		--enable-system --disable-linux-user --disable-bsd-user \
		--enable-tools --disable-guest-agent \
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
		--enable-docs --disable-werror \
		--enable-libssh \
		--enable-seccomp
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	# Split ownership (fail closed on overlap with sibling recipes):
	# linux-user emulators live in qemu-user/qemu-user-static, the
	# guest agent lives in qemu-guest-agent. This package must not
	# ship either.
	[ ! -e "$PKGDEST/usr/bin/qemu-ga" ] || { echo "ERROR: qemu main must not ship qemu-ga (qemu-guest-agent owns it)" >&2; return 1; }
	# GPU proof (headless): the staged system emulator must offer
	# the egl-headless display backend and the accelerated virtio-gpu
	# device variants. Executing the just-built binary is the grit
	# precedent (grit recipe runs "$PKGDEST/usr/bin/grit --version");
	# help queries need no KVM and no GPU.
	QEMU_SYS="$PKGDEST/usr/bin/qemu-system-x86_64"
	[ -x "$QEMU_SYS" ] || { echo "ERROR: qemu staging has no qemu-system-x86_64 emulator" >&2; return 1; }
	"$QEMU_SYS" -display help 2>/dev/null | grep -q egl-headless || { echo "ERROR: qemu staging lacks the egl-headless display backend (opengl/virgl not wired)" >&2; return 1; }
	"$QEMU_SYS" -device help 2>/dev/null | grep -q virtio-vga-gl || { echo "ERROR: qemu staging lacks virtio-vga-gl (virgl not wired)" >&2; return 1; }
	"$QEMU_SYS" -device help 2>/dev/null | grep -q virtio-gpu-gl || { echo "ERROR: qemu staging lacks virtio-gpu-gl (virgl not wired)" >&2; return 1; }
	[ -e "$PKGDEST/usr/bin/qemu-img" ] || { echo "ERROR: qemu staging is missing qemu-img (tools must stay in main)" >&2; return 1; }
}

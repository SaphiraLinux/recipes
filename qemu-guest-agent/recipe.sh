#!/bin/sh

pkgname=qemu-guest-agent
pkgver=11.1.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='QEMU Guest Agent (guest-side agent, independent of host emulators)'
license='GPL-2.0-or-later'
origin=qemu-guest-agent
repo=saphira
url=https://www.qemu.org/
source=https://download.qemu.org/qemu-11.1.1.tar.xz
sha256=079ffbff8a7111bbc89022107cbabf3bbfd614d5fc9d7cc675991196aca12482

# Guest-side agent: runs INSIDE the VM, never a host requirement.
# No qemu dependency, no emulator dependency. Hosts running system
# emulators must not be forced to install this (saphira-virtualisation
# and libvirt depend on qemu, never on qemu-guest-agent).
depends="glib"
# pcre2-dev/libffi-dev: glib-2.0.pc Requires libpcre2-8 and
# gobject-2.0.pc Requires libffi; the meson probes fail without them
# in the sysroot (qemu r6 build failure precedent).
makedepends="
	binutils
	gawk
	gcc
	glib-dev
	libffi-dev
	pcre2-dev
	saphira-linux-uapi-headers
	make
	meson
	ninja
	pkgconf
	python3
	zlib-dev
"

# Guest-agent only: no system emulators, no linux-user, no tools.
# Ships the agent binary plus its config sample. No init units are
# enabled at install (dual-init policy: if a guest image wants the
# agent as a service, the image enables it; the package never
# auto-enables). No post-install hook alters the host.
recipe_build()
{
	cd "$SRC"
	./configure --prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--disable-system --disable-linux-user --disable-bsd-user \
		--disable-tools --enable-guest-agent \
		--disable-kvm \
		-Dfdt=disabled \
		--disable-gtk --disable-sdl --disable-opengl \
		--disable-vnc --disable-spice \
		--disable-docs --disable-werror \
		--disable-libssh
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	# Ownership: /usr/share/qemu/* (pc-bios firmware, option ROMs) is
	# owned exclusively by qemu (main). The guest agent never uses it,
	# but upstream `make install` copies it for every configuration.
	# Strip it unconditionally so a future upstream install addition
	# cannot silently reintroduce a one-owner violation.
	rm -rf "$PKGDEST/usr/share/qemu"
	[ ! -e "$PKGDEST/usr/share/qemu" ] || { echo "ERROR: qemu-guest-agent must not ship /usr/share/qemu (qemu owns the firmware)" >&2; return 1; }
	# Headers belong to qemu (main): the plugin API header installs with
	# every configuration. The guest agent needs none of it.
	rm -rf "$PKGDEST/usr/include"
	[ ! -e "$PKGDEST/usr/include" ] || { echo "ERROR: qemu-guest-agent must not ship /usr/include (qemu owns the headers)" >&2; return 1; }
	# Ownership: ONLY the guest agent. Fail closed on any emulator
	# or tool leakage (those belong to qemu/qemu-user/qemu-user-static).
	[ -e "$PKGDEST/usr/bin/qemu-ga" ] || { echo "ERROR: qemu-guest-agent staging is missing qemu-ga" >&2; return 1; }
	[ ! -e "$PKGDEST/usr/bin/qemu-img" ] || { echo "ERROR: qemu-guest-agent must not ship qemu-img" >&2; return 1; }
	ls "$PKGDEST"/usr/bin/qemu-system-* >/dev/null 2>&1 && { echo "ERROR: qemu-guest-agent must not ship qemu-system-*" >&2; return 1; } || true
}

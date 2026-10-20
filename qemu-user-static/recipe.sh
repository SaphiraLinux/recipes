#!/bin/sh

pkgname=qemu-user-static
pkgver=11.1.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='QEMU Linux-user emulators (static, for foreign-architecture chroots)'
license='GPL-2.0-or-later'
origin=qemu-user-static
repo=saphira
url=https://www.qemu.org/
source=https://download.qemu.org/qemu-11.1.1.tar.xz
sha256=079ffbff8a7111bbc89022107cbabf3bbfd614d5fc9d7cc675991196aca12482

# Static binaries carry no shared-library runtime deps (suitable for
# foreign-arch chroots without copying host libraries into the guest).
depends=""
# libffi-dev/pcre2-dev are direct build inputs: glib-2.0.pc Requires
# libpcre2-8 and gobject-2.0.pc Requires libffi, so the meson
# pkg-config probes fail without them in the sysroot (qemu r6 build
# failure precedent). Those -dev packages fix the probe, but NOT the
# link below:
# NOTE (missing static libraries, reported explicitly, not silently
# worked around): this --static build needs static archives (.a) for
# glib + its transitive closure (libffi, pcre2, zlib, ...). Current
# tree state ships none of them: zlib/recipe.sh deletes libz.a,
# libffi/recipe.sh passes --disable-static, glib/pcre2 build shared
# only. The builder acceptance gate is therefore EXPECTED to fail
# closed at link time until those recipes are taught to ship static
# archives in their existing -dev outputs (no new -static splits:
# buildpkg-single moves *.a to -dev already). Do NOT revert this
# recipe to dynamic linking to get a passing build.
makedepends="
	binutils
	bison
	flex
	gawk
	gcc
	glib-dev
	libffi-dev
	pcre2-dev
	zlib-dev
	saphira-linux-uapi-headers
	make
	meson
	ninja
	pkgconf
	python3
	python3-pip
	setuptools
	wheel
"

# Static linux-user ONLY (never static system emulation: static
# system images are not portable chroot interpreters and would
# falsely satisfy the "static user-mode" requirement).
# ACCEPTANCE GATE (mandatory, builder side): readelf -d must show no
# NEEDED entries; file(1) must report statically linked; execution
# of a foreign-arch binary (e.g. aarch64 hello) via
# qemu-aarch64-static must succeed. If glib-static (or other
# *-static providers) are missing from the tree, package the genuine
# static libraries instead of reverting to dynamic linking.
recipe_build()
{
	cd "$SRC"
	./configure --prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--static \
		--disable-download \
		--disable-system --enable-linux-user --disable-bsd-user \
		--disable-tools --disable-guest-agent \
		--disable-kvm --enable-tcg \
		-Dfdt=disabled \
		--disable-gtk --disable-sdl --disable-opengl \
		--disable-vnc --disable-spice --disable-usb-redir \
		--disable-tpm \
		--disable-docs --disable-werror \
		--disable-libssh
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	# Ownership: /usr/share/qemu/* (pc-bios firmware, option ROMs) is
	# owned exclusively by qemu (main). Static linux-user interpreters
	# never use it, but upstream `make install` copies it for every
	# configuration. Strip it unconditionally so a future upstream
	# install addition cannot silently reintroduce a one-owner violation.
	rm -rf "$PKGDEST/usr/share/qemu"
	[ ! -e "$PKGDEST/usr/share/qemu" ] || { echo "ERROR: qemu-user-static must not ship /usr/share/qemu (qemu owns the firmware)" >&2; return 1; }
	# Headers belong to qemu (main): the plugin API header installs with
	# every configuration. Static interpreters need none of it.
	rm -rf "$PKGDEST/usr/include"
	[ ! -e "$PKGDEST/usr/include" ] || { echo "ERROR: qemu-user-static must not ship /usr/include (qemu owns the headers)" >&2; return 1; }
	# Ownership: static package owns ONLY *-static names. Rename the
	# dynamic-named binaries to the conventional -static names; fail
	# closed if anything else (system/tools/guest-agent) appears.
	[ ! -e "$PKGDEST/usr/bin/qemu-ga" ] || { echo "ERROR: qemu-user-static must not ship qemu-ga" >&2; return 1; }
	[ ! -e "$PKGDEST/usr/bin/qemu-img" ] || { echo "ERROR: qemu-user-static must not ship qemu-img" >&2; return 1; }
	ls "$PKGDEST"/usr/bin/qemu-system-* >/dev/null 2>&1 && { echo "ERROR: qemu-user-static must not ship qemu-system-*" >&2; return 1; } || true
	for bin in "$PKGDEST"/usr/bin/qemu-*; do
		[ -e "$bin" ] || continue
		case ${bin##*/} in
			qemu-system-*|qemu-img|qemu-nbd|qemu-io|qemu-storage-daemon|qemu-edid|qemu-ga|qemu-*-static) continue ;;
			*) mv -- "$bin" "$bin-static" ;;
		esac
	done
	ls "$PKGDEST"/usr/bin/qemu-*-static >/dev/null 2>&1 || { echo "ERROR: qemu-user-static staging has no qemu-*-static binaries" >&2; return 1; }
	# Static linkage proof (fail closed where readelf is available;
	# the builder acceptance gate re-proves with execution tests).
	if command -v readelf >/dev/null 2>&1; then
		for bin in "$PKGDEST"/usr/bin/qemu-*-static; do
			if readelf -d "$bin" 2>/dev/null | grep -q NEEDED; then
				echo "ERROR: $bin is not statically linked (has NEEDED entries)" >&2
				return 1
			fi
		done
	fi
	# binfmt_misc fragments for the static family (distinct
	# *-static.conf names so they never overlap the dynamic
	# qemu-user fragments; opt-in only, no hook, never auto-enabled).
	if [ -x "$SRC/scripts/qemu-binfmt-conf.sh" ]; then
		mkdir -p "$PKGDEST/usr/lib/binfmt.d" "$PKGDEST/usr/share/doc/qemu-user-static/binfmt"
		tmpdir=$BUILDDIR/binfmt-static
		mkdir -p "$tmpdir"
		"$SRC/scripts/qemu-binfmt-conf.sh" \
			--systemd ALL --qemu-path /usr/bin --qemu-suffix -static \
			--exportdir "$tmpdir" >/dev/null 2>&1 || true
		for conf in "$tmpdir"/qemu-*.conf; do
			[ -e "$conf" ] || continue
			base=${conf##*/}; base=${base%.conf}
			cp -- "$conf" "$PKGDEST/usr/lib/binfmt.d/$base-static.conf"
		done
		cat > "$PKGDEST/usr/share/doc/qemu-user-static/binfmt/README" <<'EOF'
qemu-user-static binfmt_misc (opt-in, disabled by default)
----------------------------------------------------------
Fragments in /usr/lib/binfmt.d/ (*-static.conf) register the
statically linked interpreters. Installing this package does NOT
activate them.
systemd: systemctl enable --now systemd-binfmt.service
OpenRC:  register manually, e.g.
  cat /usr/lib/binfmt.d/qemu-aarch64-static.conf \
    > /proc/sys/fs/binfmt_misc/register
(generated by upstream scripts/qemu-binfmt-conf.sh with
--qemu-suffix -static, filenames suffixed to avoid overlap with the
dynamic qemu-user fragments. Enable one family only.)
Static binaries run inside foreign-architecture chroots without
copying host shared libraries into the guest.
EOF
	fi
}

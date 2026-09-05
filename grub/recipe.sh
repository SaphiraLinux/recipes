pkgname=grub
pkgver=2.12
pkgrel=5
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='GRUB 2 boot loader (BIOS/i386-pc and EFI/x86_64-efi platforms, tools and scripts)'
license='GPL-3.0-or-later'
origin=grub
repo=saphira
url=https://www.gnu.org/software/grub/
# Upstream release tarball, bytes pinned:
# https://ftp.gnu.org/gnu/grub/grub-2.12.tar.xz
grub_sha256=f3c97391f7c4eaa677a78e090c7e97e6dc47b16f655f04683ebd37bef7fe0faa

depends=""
makedepends="gcc make bison flex gawk"
# Transition from the historical Stage4 split packages: a machine carrying
# grub-common/grub-bios/grub-efi must migrate to this monolith through
# normal APK replacement semantics (no --force-overwrite, no manual dels).
# apk evicts the named packages and lets this package take their files.
replaces="grub-common grub-bios grub-efi"
subpackages="$pkgname-doc"

# Saphira carries a monolithic grub (old-gen shipped grub-common +
# grub-bios + grub-efi; the worker only splits -dev/-doc/-libs, and the
# openssh precedent applies: drop the split, ship one package). Both
# platform module trees are included so grub-install works for BIOS and
# EFI from the same package. akadata policy preserved from the reference
# recipes: 30_os-prober removed (never probe other OSes), any systemd
# units upstream installs are dropped, no fonts (grub-mkfont disabled -
# no freetype dependency).

grub_build_platform()
{
	platform=$1
	arch=$2
	builddir=$BUILDDIR/$platform
	mkdir -p "$builddir" && cd "$builddir"
	# grub's genmoddep.awk uses GNU awk's asorti(); mawk cannot run it.
	AWK=/usr/bin/gawk "$SRC/configure" \
		--prefix=/usr \
		--sysconfdir=/etc \
		--with-platform=$platform \
		--with-arch=$arch \
		--disable-werror \
		--disable-grub-mkfont \
		--disable-efiemu \
		--disable-grub-mount \
		--disable-nls \
		--disable-device-mapper \
		--disable-libzfs \
		--disable-liblzma
	make -j${JOBS:-$(nproc)}
	DESTDIR="$PKGDEST" make install
}

recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 \
		-xf "$RECIPE_DIR/files/grub-2.12.tar.xz"
	echo "$grub_sha256  $RECIPE_DIR/files/grub-2.12.tar.xz" | sha256sum -c -
	# grub 2.12 release-tarball bug: grub-core/extra_deps.lst is missing,
	# which breaks out-of-tree builds (syminfo.lst has no rule for it).
	# Upstream fixed this after the release; create it empty.
	touch "$SRC/grub-core/extra_deps.lst"
	grub_build_platform pc i386
	grub_build_platform efi x86_64
	rm -f "$PKGDEST/etc/grub.d/30_os-prober"
	rm -rf "$PKGDEST/usr/lib/systemd" "$PKGDEST/lib/systemd"
	install -D -m 0644 "$SRC/COPYING" \
		"$PKGDEST/usr/share/licenses/grub/COPYING"
	# Self-verification: a grub package missing any of the modules its
	# core images need produces exactly the observed failure (grub-install
	# embeds a crippled core, rescue sees no disks). Prove the payload is
	# self-contained at build time; both platform trees must be complete.
	# Note: there is deliberately no x86_64-efi/efidisk.mod - on EFI the
	# disk driver is compiled into kernel.exec (kernel_exec-efidisk.o),
	# not shipped as a loadable module; efi_gop.mod is the EFI-specific
	# loadable proof instead. Verified against the published r2 and the
	# historical r0 grub-efi tree, neither of which contains efidisk.mod.
	for module in \
		usr/lib/grub/i386-pc/kernel.img \
		usr/lib/grub/i386-pc/biosdisk.mod \
		usr/lib/grub/i386-pc/ext2.mod \
		usr/lib/grub/i386-pc/normal.mod \
		usr/lib/grub/i386-pc/part_msdos.mod \
		usr/lib/grub/i386-pc/part_gpt.mod \
		usr/lib/grub/x86_64-efi/kernel.img \
		usr/lib/grub/x86_64-efi/efi_gop.mod \
		usr/lib/grub/x86_64-efi/ext2.mod \
		usr/lib/grub/x86_64-efi/normal.mod \
		usr/lib/grub/x86_64-efi/part_gpt.mod; do
		[ -f "$PKGDEST/$module" ] || {
			printf 'grub: build produced an incomplete payload: missing %s\n' "$module" >&2
			exit 1
		}
	done
	[ -n "$(find "$PKGDEST/usr/lib/grub/i386-pc" -name '*.mod' | head -1)" ] &&
		[ -n "$(find "$PKGDEST/usr/lib/grub/x86_64-efi" -name '*.mod' | head -1)" ] || {
		printf 'grub: build produced empty platform module trees\n' >&2
		exit 1
	}
}

recipe_install() {
	:
}

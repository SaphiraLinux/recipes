pkgname=grub
pkgver=2.14
pkgrel=4
# r4: split grub-tools (manual/rescue utilities) out of the monolith;
# base keeps installer, probe, mkconfig and the module payload. Runtime
# deps follow proven linkage only (fuse/intl out of base). Payload change.
# r3: discover Saphira early-firmware images (earlyfw-<release>.img)
# in 10_linux like initramfs ones (listed first, so the current name
# wins over stale initramfs-<release>.img orphans). Payload change.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='GRUB 2 boot loader (platform modules, tools and scripts)'
license='GPL-3.0-or-later'
origin=grub
repo=saphira
url=https://www.gnu.org/software/grub/
# Upstream release tarball, bytes pinned:
# https://ftp.gnu.org/gnu/grub/grub-2.14.tar.xz
# Signature file grub-2.14.tar.xz.sig, key
# BE5C 2320 9ACD DACE B20D B0A2 8C81 89F1 988C 2166 (Daniel Kiper,
# announced 2026-01-14). Egg's minimal gnupg (no keyboxd/dirmngr)
# could only parse the sig and confirm the key id, so the sha256
# below is the enforced gate here and fetch-vendor-sources re-verifies
# it on every fetch; a builder with full gnupg re-verifies the sig.
vendor=https://ftp.gnu.org/gnu/grub/grub-2.14.tar.xz
sha256=bc8d3c73535b8838d8c8e2654d73edc4e6ae8c8acdb45d5df5dc9a1547446d43

# grub-mkconfig and /etc/grub.d/10_linux are shell: they require
# sed and grep at RUNTIME (proven by image-build failure without
# them: "10_linux: line 35: sed: command not found"). cut/sort/tr
# come from coreutils via the base group; gettext_printf falls back
# inside grub-mkconfig_lib, so gettext stays out.
# Runtime libs for the enabled feature set (each --enable below names
# its consumer): grub-mount needs fuse3, liblzma needs xz,
# device-mapper needs lvm2-libs (lib only - the lvm2 tools never enter
# a grub closure), NLS tooling is build-time only (msgfmt compiles .mo
# catalogs; no shipped binary links libintl), grub-protect needs
# libtasn1. Base carries only what its resident binaries link; the
# manual/rescue tools in grub-tools carry their own edges there.
# No libzfs runtime: host-side libzfs stays disabled (see
# below), so the bootloader never drags the CDDL userspace into
# every install; native zfs.mod is the boot path.
depends="
	sed
	grep
	xz
	lvm2-libs
"
makedepends="gcc make bison flex gawk pkgconf gettext gettext-dev fuse3-dev xz-dev lvm2-dev libtasn1-dev"
# Transition from the historical Stage4 split packages: a machine carrying
# grub-common/grub-bios/grub-efi must migrate to this monolith through
# normal APK replacement semantics (no --force-overwrite, no manual dels).
# apk evicts the named packages and lets this package take their files.
replaces="grub-common grub-bios grub-efi"
subpackages="$pkgname-doc grub-tools"

# Saphira carries a monolithic grub (old-gen shipped grub-common +
# grub-bios + grub-efi; the worker only splits -dev/-doc/-libs, and the
# openssh precedent applies: drop the split, ship one package). Each
# build produces only its SAPHIRA_ARCH platform set (x86_64: i386-pc and
# x86_64-efi; aarch64: arm64-efi), so an x86_64 package never carries
# AArch64 binaries. Saphira policy preserved from the reference
# recipes: 30_os-prober removed (never probe other OSes), any systemd
# units upstream installs are dropped.
#
# Feature decisions (every --disable-* reviewed for 2.14; explicit
# --enable-* fails closed at configure time when deps are missing, so a
# missing header is a loud builder error, never a silent feature drop):
# --disable-efiemu: legacy 16-bit BIOS emulation for UEFI drivers.
#   Obsolete upstream, unmaintained, no Saphira use case: native
#   i386-pc covers BIOS boot, native *-efi covers UEFI. Kept disabled
#   as an obsolete feature, not a simplification.
# --disable-grub-mkfont: BLOCKED_BY_freetype. grub-mkfont needs
#   freetype2 headers and there is no freetype recipe in the tree
#   (checked 2026-10-17). Enabling requires porting freetype first
#   (grub -> BLOCKED_BY_freetype); fonts/themes stay minimal until then.
# --enable-grub-mount: fuse3-dev present (fuse 3.18.2). Host-side
#   filesystem inspection; musl-compatible.
# --enable-nls: gettext/gettext-dev present. Internationalisation is
#   required functionality, not optional.
# --enable-device-mapper: lvm2 2.03.39 vendors libdm/libdevmapper.h
#   and installs it (no -dev split in that recipe, headers ride the
#   main payload). LVM boot support, including the 2.14 LV integrity
#   and cachevol handling.
# --enable-liblzma: xz-dev present. Compressed-kernel/module support.
# --disable-libzfs: deliberate packaging decision, not a simplification.
#   The native zfs.mod filesystem driver (the actual boot path) is
#   self-contained and always built as part of the complete module
#   tree below. Host-side libzfs linkage would only change grub-probe
#   pool-name conveniences while imposing a libzfs/libnvpair runtime
#   dependency (CDDL saphira-zfs-userspace, itself requiring a staged
#   kernel tree to build) on every bootloader install, including
#   non-ZFS machines. grub-probe detects ZFS pools through its native
#   driver; the disposable-image boot tests prove it. Revisit only
#   with a measured grub-probe gap, never speculatively.
# --enable-grub-protect: libtasn1-dev present (4.19.0). TPM2-adjacent
#   key-protector tooling ships with the 2.14 feature set.
# Not forced (upstream defaults stand): grub-emu-sdl/sdl2 (would drag
# SDL under the headless policy: no X/SDL/GTK in the universe),
# grub-themes (needs mkfont-rendered fonts: same freetype block),
# mm-debug/cache-stats/boot-time (diagnostic builds, not product),
# stack-protector (toolchain default applies).

grub_build_platform()
{
	# $1 = autoconf target cpu, $2 = grub platform, $3 = module dir name.
	cpu=$1
	platform=$2
	target=$3
	builddir=$BUILDDIR/build-$target
	stagedir=$BUILDDIR/stage-$target
	rm -rf "$builddir" "$stagedir"
	mkdir -p "$builddir" "$stagedir"
	cd "$builddir"
	# grub's genmoddep.awk uses GNU awk's asorti(); mawk cannot run it.
	# Linker selection: configure prefers -Wl,--image-base when the
	# linker merely ACCEPTS it, but on ELF --image-base leaves headers
	# before .text (Saphira ld 2.46.1: .text at 0x90b4 for base 0x9000,
	# reproduced locally) while grub-mkimage requires .text exactly AT
	# the link address ("miscompiled ... ld.gold bug?"). -Ttext places
	# .text exactly (proven locally: 0x9000). Preseed the probe
	# negative so configure selects -Ttext. If upstream ever renames
	# this cache variable the preseed stops working and the mkimage
	# dependency check below fails closed.
	ax_cv_check_ldflags___Wl___image_base_0x400000=no
	export ax_cv_check_ldflags___Wl___image_base_0x400000
	AWK=/usr/bin/gawk "$SRC/configure" \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--target=$cpu \
		--with-platform=$platform \
		--disable-werror \
		--disable-efiemu \
		--disable-grub-mkfont \
		--enable-grub-mount \
		--enable-nls \
		--enable-device-mapper \
		--enable-liblzma \
		--disable-libzfs \
		--enable-grub-protect
	# Out-of-tree builds need grub-core/extra_deps.lst in the BUILD
	# tree: syminfo.lst is catted from kernel_syms.lst + extra_deps.lst
	# with no make rule to create it (2.14 still omits it, same as the
	# 2.12 tarball; the $SRC touch below only covers in-tree paths).
	touch grub-core/extra_deps.lst
	make -j${JOBS:-$(nproc)}
	DESTDIR="$stagedir" make install
}

grub_merge_stage()
{
	# Merge one platform stage into PKGDEST with no concealed
	# collisions. Platform module trees must be disjoint; common host
	# files are expected byte-identical across stages (same source,
	# same flags) except tools embedding a compiled-in default
	# platform (grub-install prints its own default target). Identical
	# files merge silently, differing files are recorded to the merge
	# report and the later stage wins, so the build log names every
	# overlap instead of hiding it.
	stage=$1
	tag=$2
	list=$BUILDDIR/files-$tag.list
	( cd "$stage" && find . -mindepth 1 | LC_ALL=C sort ) > "$list"
	while IFS= read -r entry; do
		src=$stage/$entry
		dst=$PKGDEST/$entry
		if [ -f "$src" ] || [ -L "$src" ]; then
			if [ -e "$dst" ] || [ -L "$dst" ]; then
				if cmp -s "$src" "$dst"; then
					:
				else
					printf 'grub merge: %s differs between stages, %s wins\n' \
						"$entry" "$tag" >> "$BUILDDIR/merge-report.txt"
					rm -f "$dst"
					cp -a "$src" "$dst"
				fi
			else
				mkdir -p "$(dirname "$dst")"
				cp -a "$src" "$dst"
			fi
		elif [ -d "$src" ]; then
			mkdir -p "$dst"
		fi
	done < "$list"
}

recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 \
		-xf "$RECIPE_DIR/files/grub-2.14.tar.xz"
	echo "$sha256  $RECIPE_DIR/files/grub-2.14.tar.xz" | sha256sum -c -
	# grub release tarballs omit grub-core/extra_deps.lst, which
	# breaks out-of-tree builds (syminfo.lst has no rule for it).
	# touch(1) only creates when missing, never clobbers a shipped file.
	touch "$SRC/grub-core/extra_deps.lst"
	# musl has no glibc-only <sys/cdefs.h>; the shipped generated
	# gnulib header hard-codes a glibc build host (#if 1) and breaks
	# host-tool preprocessing (grub_fstest.pp). The fallbacks in the
	# file cover every macro used, so include the system header on
	# glibc only. The .in.h template is already correct via
	# @HAVE_SYS_CDEFS_H@ and needs no change.
	patch -p1 -d "$SRC" < "$RECIPE_DIR/files/musl-gnulib-sys-cdefs.patch"
	# Saphira 10_linux identity: saphira classes/IDs (never upstream
	# gnu-linux) and no zdb fallback (native grub-probe is the ZFS
	# path; zdb is absent from product images). Applied to the .in
	# template so both platform builds generate it identically.
	patch -p1 -d "$SRC" < "$RECIPE_DIR/files/10_linux-saphira-branding.patch"
	# Saphira early-firmware discovery: firmware-only cpios named
	# earlyfw-<release>.img must produce initrd lines exactly like
	# the initramfs names stock 10_linux matches (verified applying
	# cleanly pre-commit; keep the header counts exact, no fuzz).
	patch -p1 -d "$SRC" < "$RECIPE_DIR/files/earlyfw-10-linux-discovery.patch"
	: > "$BUILDDIR/merge-report.txt"
	mkdir -p "$PKGDEST"
	case "${SAPHIRA_ARCH:-x86_64}" in
		x86_64)
			grub_build_platform i386 pc i386-pc
			grub_build_platform x86_64 efi x86_64-efi
			grub_merge_stage "$BUILDDIR/stage-i386-pc" first-i386-pc
			grub_merge_stage "$BUILDDIR/stage-x86_64-efi" second-x86_64-efi
			;;
		aarch64)
			grub_build_platform aarch64 efi arm64-efi
			grub_merge_stage "$BUILDDIR/stage-arm64-efi" only-arm64-efi
			;;
		*)
			printf 'grub: unsupported SAPHIRA_ARCH: %s (want x86_64|aarch64)\n' \
				"${SAPHIRA_ARCH:-x86_64}" >&2
			return 1
			;;
	esac
	rm -f "$PKGDEST/etc/grub.d/30_os-prober"
	rm -rf "$PKGDEST/usr/lib/systemd" "$PKGDEST/lib/systemd"
	install -D -m 0644 "$SRC/COPYING" \
		"$PKGDEST/usr/share/licenses/grub/COPYING"
	# Completeness, not a hand-picked subset: every module the build
	# produced must be installed, for every target of this arch.
	# (EFI has no efidisk.mod by design: on EFI the disk driver is
	# compiled into kernel.exec, not shipped as a loadable module.
	# The built-vs-installed comparison below encodes exactly that:
	# only built modules are required.)
	for target in $(cd "$BUILDDIR" && ls -d stage-*/ | sed 's#stage-##;s#/##'); do
		builddir=$BUILDDIR/build-$target
		moddir=$PKGDEST/usr/lib/grub/$target
		[ -d "$moddir" ] || {
			printf 'grub: missing platform module tree: %s\n' "$moddir" >&2
			return 1
		}
		[ -n "$(find "$moddir" -name '*.mod' | head -1)" ] || {
			printf 'grub: empty platform module tree: %s\n' "$moddir" >&2
			return 1
		}
		for built in "$builddir"/grub-core/*.mod; do
			[ -f "$moddir/$(basename "$built")" ] || {
				printf 'grub: built module not installed: %s -> %s\n' \
					"$built" "$moddir" >&2
				return 1
			}
		done
		# Boot-critical and task-mandated modules named explicitly so
		# a regression fails here, not in a rescue shell: normal and
		# kernel images, ext2 (covers ext2/3/4), zfs (native driver;
		# the libzfs decision above does not affect it), GPT/MBR
		# partition maps, BIOS disk driver where applicable.
		for required in kernel.img normal.mod ext2.mod zfs.mod part_gpt.mod; do
			[ -f "$moddir/$required" ] || {
				printf 'grub: missing required module %s in %s\n' \
					"$required" "$moddir" >&2
				return 1
			}
		done
		case $target in
			i386-pc)
				for required in biosdisk.mod part_msdos.mod; do
					[ -f "$moddir/$required" ] || {
						printf 'grub: missing required module %s in %s\n' \
							"$required" "$moddir" >&2
						return 1
					}
				done
				;;
		esac
		# Module dependency check: resolve a core image through the
		# installed tree, including the native ZFS driver. This
		# exercises moddep resolution the way grub-install does.
		# (-p embeds the boot prefix string; the image is discarded,
		# so the value is arbitrary.)
		"$PKGDEST/usr/bin/grub-mkimage" -d "$moddir" \
			-p /boot/grub -O $target \
			-o "$BUILDDIR/test-core-$target.img" \
			normal ext2 zfs part_gpt || {
			printf 'grub: grub-mkimage dependency check failed for %s\n' \
				"$target" >&2
			return 1
		}
	done
	# Host tools the boot path needs. install/probe/mkconfig are
	# sbin_PROGRAMS/sSCRIPTS (/usr/sbin); mkimage/mount/fstest/
	# protect are bin_PROGRAMS (/usr/bin). Assert the split explicitly
	# so a future upstream reshuffle fails here, not at image build.
	for tool in usr/sbin/grub-install usr/sbin/grub-mkconfig \
		usr/sbin/grub-probe usr/bin/grub-fstest \
		usr/bin/grub-mkimage usr/bin/grub-mount \
		usr/bin/grub-protect; do
		[ -x "$PKGDEST/$tool" ] || {
			printf 'grub: missing host tool: %s\n' "$tool" >&2
			return 1
		}
	done
	# Saphira 10_linux identity gate: the packaged script must carry
	# the established saphira classes/IDs and no zdb fallback. An
	# upstream rebase that touches these lines fails here, before a
	# regressed grub.cfg can reach any machine.
	ten_linux=$PKGDEST/etc/grub.d/10_linux
	[ -f "$ten_linux" ] || {
		printf 'grub: missing etc/grub.d/10_linux\n' >&2
		return 1
	}
	for required in \
		'CLASS="--class saphira --class linux --class os"' \
		'saphira-$version-$type-$boot_device_id' \
		'saphira-simple-$boot_device_id' \
		'saphira-advanced-$boot_device_id'; do
		grep -Fq "$required" "$ten_linux" || {
			printf 'grub: 10_linux lost Saphira branding: %s\n' \
				"$required" >&2
			return 1
		}
	done
	for forbidden in \
		'CLASS="--class gnu-linux' \
		'gnulinux-' \
		'zdb -l'; do
		if grep -Fq "$forbidden" "$ten_linux"; then
			printf 'grub: 10_linux carries upstream residue: %s\n' \
				"$forbidden" >&2
			return 1
		fi
	done
	# Full payload manifest is build evidence (kept in the retained
	# workspace next to the log, not in the package).
	( cd "$PKGDEST" && find . -mindepth 1 | LC_ALL=C sort ) \
		> "$BUILDDIR/grub-manifest-${SAPHIRA_ARCH:-x86_64}.txt"
	printf 'grub: payload %s entries, merge report:\n' \
		"$(wc -l < "$BUILDDIR/grub-manifest-${SAPHIRA_ARCH:-x86_64}.txt")"
	cat "$BUILDDIR/merge-report.txt"
	# Split-hygiene guard (see the depends comment): only grub-mount may
	# link fuse, and nothing links intl (msgfmt is build-time). lvm2-libs,
	# liblzma and libtasn1 edges live wherever linkage proves them, base
	# or tools alike - so a re-added makedepend that relinks (autodetect)
	# fails the build instead of resurrecting an install depend. readelf
	# rides the gcc closure (proven by builds); no binutils line needed.
	for bin in "$PKGDEST"/usr/bin/grub-* "$PKGDEST"/usr/sbin/grub-*; do
		[ -f "$bin" ] || continue
		case $(basename "$bin") in
			grub-mount) ;;
			*)
				if readelf -d "$bin" | grep -q libfuse; then
					printf 'grub: %s links libfuse (only grub-mount may)\n' \
						"$bin" >&2
					return 1
				fi
				;;
		esac
		if readelf -d "$bin" | grep -q libintl; then
			printf 'grub: %s links libintl (msgfmt is build-time only)\n' \
				"$bin" >&2
			return 1
		fi
	done
}

recipe_install() {
	:
}

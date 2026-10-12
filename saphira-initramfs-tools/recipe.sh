#!/bin/sh
pkgname=saphira-initramfs-tools
pkgver=0.1
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Saphira initramfs generator, static-musl /init and the early-userspace hook framework'
license='BUSL-1.1'
origin=saphira-initramfs-tools
repo=saphira
url=https://saphira.vm2.uk/
#
# r1: the first initramfs tooling. One generator, used twice: the media builder
# makes the installer initramfs from the installer root, and the installer
# makes the destination machine's initramfs from the newly installed root.
#
# DEPENDENCY SHAPE, which is the interesting part:
#
#   makedepends  gcc musl-dev. The static /init and the ELF closure helper are
#                built ONCE, here, and shipped in the payload. Generating an
#                initramfs on an installed machine must not require a
#                compiler, and the alternative -- compiling /init on demand --
#                would put gcc in the runtime dependency set of every machine.
#
#   r2: five defects the T1 suite found in r1, all of which produced a
#       WRONG ARCHIVE rather than an error. r1 is superseded and must not be
#       used to generate anything:
#         - cpio members were absolute, so every entry carried the build-host
#           prefix and no member was where the kernel looks for it;
#         - /init was staged at its packaged path instead of the archive root,
#           so the kernel would have found nothing to execute;
#         - the module closure popped nothing from its queue and stopped after
#           one hop, yielding a closure with no dependencies;
#         - the same walk appended modules.dep PATHS into a queue keyed by bare
#           module name, so every follow-up lookup missed;
#         - switch_root was requested from /usr/bin, where non-usrmerged
#           Saphira does not put it.
#       A tool that emits a plausible archive of the wrong contents is worse
#       than one that refuses, which is why verify_archive re-reads the archive
#       and refuses build-host paths before anything is published.
#
#   depends      cpio zstd kmod util-linux. The generator shells out to cpio
#                (newc), zstd (deterministic frame), and uses kmod's
#                module metadata through the MODULE FILES rather than by
#                running modprobe, so kmod is here for the metadata contract
#                and util-linux for switch_root.
#
#   NOT binutils. Reading DT_NEEDED and PT_INTERP is exactly what a program
#   would do with readelf, and making binutils a runtime dependency purely so a
#   machine can regenerate its own initramfs is a bad trade. The closure
#   helper is ~300 lines of C in this package for that reason.
depends="
	cpio
	kmod
	util-linux
	zstd
"
makedepends="
	gcc
	musl-dev
"

recipe_build()
{
	# Sources are named absolutely: the worker's working directory is not the
	# recipe's files directory, and a bare relative path fails at compile time
	# rather than at anything a human would recognise.
	#
	# Outputs go to a fixed absolute location under the build root so
	# recipe_install can find them regardless of the working directory.
	local src=$RECIPE_DIR/files
	local out=${BUILD_ROOT:-/build}/saphira-initramfs-tools.out
	local cc=${CC:-gcc}

	mkdir -p "$out" || return 1

	# -fPIE with -static-pie, and not -static-pie alone: the compiler needs
	# to be told to generate position-independent code before the linker is
	# asked to make a PIE, or it fails with "relocation R_X86_64_32 ... can
	# not be used when making a PIE object". static-pie is the mode the musl
	# recipe already asserts libc.a can support, so the same mode is used
	# here rather than a plain -static that would quietly drop the
	# static-PIE capability the toolchain policy maintains.
	$cc -std=gnu11 -Os -Wall -Wextra -fPIE -static-pie \
		-o "$out/init" "$src/init.c" || return 1
	$cc -std=gnu11 -Os -Wall -Wextra -fPIE -static-pie \
		-o "$out/elf-closure" "$src/elf-closure.c" || return 1

	# Assert the property the package exists to guarantee, rather than
	# trusting the link line. A dynamically linked /init would be a silent
	# regression that still produced a working archive on the build host and
	# failed only at boot, which is the worst possible time to find out.
	if readelf -l "$out/init" 2>/dev/null | grep -q 'program interpreter'; then
		echo "ERROR: init is dynamically linked; it must be static" >&2
		return 1
	fi
	if readelf -d "$out/init" 2>/dev/null | grep -q 'NEEDED'; then
		echo "ERROR: init has shared library dependencies" >&2
		return 1
	fi
	echo "init: static-pie, no interpreter, no NEEDED entries"
}

recipe_install()
{
	local out=${BUILD_ROOT:-/build}/saphira-initramfs-tools.out
	local src=$RECIPE_DIR/files

	test -x "$out/init" || { echo "ERROR: init was not built" >&2; return 1; }
	test -x "$out/elf-closure" || { echo "ERROR: elf-closure was not built" >&2; return 1; }

	install -D -m 0755 "$src/saphira-mkinitramfs" \
		"$PKGDEST/usr/sbin/saphira-mkinitramfs"
	install -D -m 0755 "$out/init" \
		"$PKGDEST/usr/lib/saphira/initramfs/init"
	install -D -m 0755 "$out/elf-closure" \
		"$PKGDEST/usr/libexec/saphira/elf-closure"
	install -D -m 0644 "$src/initramfs.conf" \
		"$PKGDEST/etc/saphira/initramfs.conf"
	install -D -m 0644 "$src/saphira-mkinitramfs.8" \
		"$PKGDEST/usr/share/man/man8/saphira-mkinitramfs.8"
	install -D -m 0644 "$src/build-hooks.d/README" \
		"$PKGDEST/usr/share/doc/saphira-initramfs-tools/build-hooks.d.README"
}

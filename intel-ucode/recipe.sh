#!/bin/sh

pkgname=intel-ucode
pkgver=20260925
pkgrel=1
# r1: Intel processor microcode for early loading (2026-10-23).
# Physical Intel hosts need microcode applied before normal kernel
# initialisation; the late loader (/sys/.../reload) cannot cover
# early boot. Upstream: Intel-Linux-Processor-Microcode-Data-Files
# tag microcode-20260925 (hash pinned below; GitHub publishes no
# signature for these archives, so the hash is recorded from the
# vendored bytes and re-verified on every build - stated, not hidden).
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Intel CPU microcode updates with early-loading boot image"
license="LicenseRef-Intel-Ucode"
origin=intel-ucode
repo=saphira
url=https://github.com/intel/Intel-Linux-Processor-Microcode-Data-Files
source=https://github.com/intel/Intel-Linux-Processor-Microcode-Data-Files/archive/refs/tags/microcode-20260925.tar.gz
sha256=0ec19023dad1e6dd0c5909174b8dff2555b91cf01671e36271a1ef36655c0cfc

# No runtime depends: the payload is data (blobs), a static boot image
# and a reporting script. The grub hook no-ops where GRUB is absent.
depends=""
makedepends="cpio"

recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/microcode-20260925.tar.gz" | sha256sum -c -
}

recipe_install()
{
	# Blobs verbatim (Intel's licence permits redistribution in binary
	# form WITHOUT modification: no rename, no trim, no patch).
	# intel-ucode-with-caveats/ is deliberately EXCLUDED (Intel ships
	# those for kernels carrying separate late-loader patches, which
	# Saphira does not have - see Intel README).
	mkdir -p "$PKGDEST/lib/firmware/intel-ucode"
	tar --no-same-owner -C "$PKGDEST/lib/firmware/intel-ucode" \
		--strip-components=2 --wildcards \
		-xf "$RECIPE_DIR/files/microcode-20260925.tar.gz" \
		'*/intel-ucode/*' || return 1
	[ -n "$(ls -A "$PKGDEST/lib/firmware/intel-ucode")" ] ||
		{ echo "ERROR: no microcode blobs staged" >&2; return 1; }
	# Early image: ONE uncompressed cpio holding the concatenated
	# bundle as kernel/x86/microcode/GenuineIntel.bin. Concatenation
	# is the kernel-documented early container (the loader scans the
	# bundle for the running CPU's signature and ignores the rest);
	# the blobs themselves are byte-identical to upstream. Sorted
	# input + fixed cpio metadata keep the image reproducible.
	# Uncompressed and first on the initrd line is MANDATORY: the
	# early loader cannot decompress, and only the first initramfs
	# is scanned. GRUB's stock early list already names
	# intel-ucode.img, so no grub configuration changes are needed.
	work=$PKGDEST/boot/.ucode-build
	mkdir -p "$work/kernel/x86/microcode"
	for b in "$PKGDEST"/lib/firmware/intel-ucode/*; do
		[ -f "$b" ] || continue
		cat -- "$b"
	done > "$work/kernel/x86/microcode/GenuineIntel.bin"
	[ -s "$work/kernel/x86/microcode/GenuineIntel.bin" ] ||
		{ echo "ERROR: empty microcode bundle" >&2; return 1; }
	( cd "$work" && find kernel -print0 | LC_ALL=C sort -z |
		cpio --null --create --format=newc --quiet \
			--owner=0:0 --reproducible ) \
		> "$PKGDEST/boot/intel-ucode.img" ||
		{ echo "ERROR: cpio failed" >&2; return 1; }
	rm -rf "$work"
	install -D -m 0755 "$RECIPE_DIR/files/intel-ucode-status" \
		"$PKGDEST/usr/sbin/intel-ucode-status"
	install -D -m 0644 "$RECIPE_DIR/files/README" \
		"$PKGDEST/usr/share/doc/intel-ucode/README"
	# Intel licence text, verbatim (redistribution condition 1).
	mkdir -p "$PKGDEST/usr/share/licenses/intel-ucode"
	tar --no-same-owner -C "$PKGDEST/usr/share/licenses/intel-ucode" \
		--strip-components=1 --wildcards \
		-xf "$RECIPE_DIR/files/microcode-20260925.tar.gz" \
		'*/license' || return 1
	# grub.cfg regeneration on install/upgrade (activation is the
	# initrd line + a reboot, never the package alone).
	install -d -m 0755 "$PKGDEST/usr/share/saphira/hooks.d/$pkgname"
	install -m 0755 "$RECIPE_DIR/files/hooks-grub-mkconfig" \
		"$PKGDEST/usr/share/saphira/hooks.d/$pkgname/post-install"
	install -m 0755 "$RECIPE_DIR/files/hooks-grub-mkconfig" \
		"$PKGDEST/usr/share/saphira/hooks.d/$pkgname/post-upgrade"
	test -f "$PKGDEST/boot/intel-ucode.img"
}

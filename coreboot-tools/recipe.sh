#!/bin/sh
pkgname=coreboot-tools
pkgver=26.09
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Coreboot host firmware utilities (cbfstool, ifdtool, inteltool and friends)'
license='GPL-2.0-only'
origin=coreboot-tools
repo=saphira
url=https://www.coreboot.org/
# Current stable release at packaging time (26.09 > queue-stale 25.12).
# Single source recipe: the full release tarball is vendored once and
# each standalone util/ tool is built by its own Makefile. No coreboot
# firmware image is built.
source=https://coreboot.org/releases/coreboot-26.09.tar.xz
sha256=cd980020c811627fe816eee933de15723681c9bcf370f7a680c41f0663c207da

# -lpci/-lz link the hardware tools (inteltool, intelmetool,
# superiotool, bucts). cbfstool vendors its lzma/lz4 sources in-tree.
depends="pciutils zlib"
# vim supplies xxd, which cbfstool needs to generate its trampoline.
# pciutils-dev/zlib-dev feed the -lpci/-lz probes. saphira-linux-uapi-headers
# for cbmem and friends. WERROR stays at upstream default.
# patches/cbmem-endian-include.patch: cbmem.c uses le32toh/le16toh
# without including <endian.h> (glibc tolerated it, musl errors).
makedepends="binutils gcc make pciutils-dev pkgconf saphira-linux-uapi-headers vim zlib-dev"

# Tools built on every architecture (pure parsers/generators, no HW I/O).
PORTABLE_TOOLS="cbfstool ifdtool smmstoretool"
# x86 chipset/EC/MSR/CMOS hardware access: meaningless elsewhere.
X86_TOOLS="cbmem ectool intelmetool inteltool intelvbttool superiotool nvramtool bucts"

recipe_build() {
	CB_BALL="$RECIPE_DIR/files/coreboot-${pkgver}.tar.xz"
	echo "$sha256  $CB_BALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$CB_BALL"
	# Re-extraction above refreshes the worker-prepared tree, so apply
	# our patches explicitly (saphira-kernel precedent).
	for patch_file in "$RECIPE_DIR"/patches/*.patch; do
		[ -f "$patch_file" ] || continue
		patch -Np1 -d "$SRC" < "$patch_file"
	done
	TOOLS="$PORTABLE_TOOLS"
	case "${SAPHIRA_ARCH:-x86_64}" in
		x86_64) TOOLS="$TOOLS $X86_TOOLS" ;;
		aarch64) ;;
		*) echo "ERROR: unsupported SAPHIRA_ARCH for coreboot-tools: ${SAPHIRA_ARCH:-x86_64}" >&2; return 1 ;;
	esac
	# cbfstool dir yields the whole CBFS family in one build, excluding
	# the cmocka unit-test target: cbfstool, ifittool, fmaptool,
	# rmodtool, ifwitool (merged upstream; no separate ifwitool dir
	# remains), cbfs-compression-tool, elogtool, cse_fpt, cse_serger.
	if [ -n "$(echo " $TOOLS " | grep ' cbfstool ')" ]; then
		make -C "$SRC/util/cbfstool" -j${JOBS:-$(nproc)} CC=gcc \
			PREFIX=/usr cbfstool ifittool fmaptool rmodtool ifwitool \
			cbfs-compression-tool elogtool cse_fpt cse_serger
	fi
	for tool in $TOOLS; do
		[ "$tool" = "cbfstool" ] && continue
		if [ "$tool" = "bucts" ]; then
			# No git in the namespace; stamp the release version
			# instead of an empty git-describe string.
			make -C "$SRC/util/$tool" -j${JOBS:-$(nproc)} \
				CC=gcc PREFIX=/usr VERSION="${pkgver}"
			continue
		fi
		make -C "$SRC/util/$tool" -j${JOBS:-$(nproc)} \
			CC=gcc PREFIX=/usr
	done
}

recipe_install() {
	TOOLS="$PORTABLE_TOOLS"
	case "${SAPHIRA_ARCH:-x86_64}" in
		x86_64) TOOLS="$TOOLS $X86_TOOLS" ;;
		aarch64) ;;
	esac
	for tool in $TOOLS; do
		[ "$tool" = "cbfstool" ] && continue
		[ "$tool" = "bucts" ] && continue
		make -C "$SRC/util/$tool" CC=gcc PREFIX=/usr DESTDIR="$PKGDEST" install
	done
	# bucts ships no install target; install the binary manually.
	if [ -n "$(echo " $TOOLS " | grep ' bucts ')" ]; then
		install -D -m 0755 "$SRC/util/bucts/bucts" "$PKGDEST/usr/sbin/bucts"
	fi
	# cbfstool's install target depends on all (which includes the
	# cmocka unit-test build); install the built family manually.
	if [ -n "$(echo " $TOOLS " | grep ' cbfstool ')" ]; then
		for bin in cbfstool ifittool fmaptool rmodtool ifwitool \
				cbfs-compression-tool elogtool cse_fpt cse_serger; do
			install -D -m 0755 "$SRC/util/cbfstool/$bin" \
				"$PKGDEST/usr/bin/$bin"
		done
	fi
}

# Deliberate non-shipments, not silent:
# - util/msrtool: duplicates the packaged msr-tools 1.3 recipe.
# - util/ifwitool as a separate fetch: merged into util/cbfstool
#   upstream; its binary still ships from the cbfstool build above.
# - util/spdtool (spdtool.py): needs the Python crc16 module (PyPI 0.1.1,
#   py2-era C sdist, no wheel, unpackaged) — follow-up material.
# - util/amdfwtool, futility, intelp2m (Go), uio_usbdebug, kbc1126,
#   pmh7tool, post, spkmodem_recv: out of the firmware-inspection scope
#   for this toolkit (AMD PSP bundling, ChromeOS, token-converter,
#   live-HW debug, vendor-EC specifics, POST cards, modem audio).
# - man pages: only inteltool/superiotool/nvramtool ship .8 pages
#   upstream; those install with their tools above. No sphinx stack is
#   involved (plain .8 files, no generation step).

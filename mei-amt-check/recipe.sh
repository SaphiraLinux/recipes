#!/bin/sh
pkgname=mei-amt-check
# No upstream tags; version is the HEAD commit date, commit pinned below.
pkgver=20180507
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Intel AMT presence/provisioning checker via /dev/mei (read-only)'
license='GPL-2.0-only'
origin=mei-amt-check
repo=saphira
url=https://github.com/mjg59/mei-amt-check
# HEAD ec921d1e0a2ac770e7835589a28b85bc2f15200c (2018-05-07). The tool is
# tiny and stable; this is the canonical reference behind fwupd's AMT
# plugin as well. No install target upstream; installed manually.
source=https://github.com/mjg59/mei-amt-check/archive/ec921d1e0a2ac770e7835589a28b85bc2f15200c.tar.gz
sha256=d84e72316a9a3374dac8a7f40da878dd0ac8cf29ee92837c2719e0f54b710f9e

# Read-only by design: opens /dev/mei* and queries AMT version; never
# provisions or alters anything. /dev/mei* appears via the newly enabled
# CONFIG_INTEL_MEI_ME (TXE/GSC variants where hardware provides them).
depends=""
# x86-only: talks Intel ME/AMT over MEI.
makedepends="binutils gcc make saphira-linux-uapi-headers"

recipe_build() {
	case "${SAPHIRA_ARCH:-x86_64}" in
		x86_64) ;;
		*) echo "ERROR: mei-amt-check is x86_64-only (Intel MEI/AMT): ${SAPHIRA_ARCH:-x86_64}" >&2; return 1 ;;
	esac
	MEI_BALL="$RECIPE_DIR/files/ec921d1e0a2ac770e7835589a28b85bc2f15200c.tar.gz"
	echo "$sha256  $MEI_BALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$MEI_BALL"
	make -C "$SRC" -j${JOBS:-$(nproc)} CC=gcc
}

recipe_install() {
	install -D -m 0755 "$SRC/mei-amt-check" "$PKGDEST/usr/sbin/mei-amt-check"
}

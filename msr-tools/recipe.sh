#!/bin/sh
pkgname=msr-tools
pkgver=1.3
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='x86 MSR and CPUID access tools (rdmsr, wrmsr, cpuid)'
license='GPL-2.0-or-later'
origin=msr-tools
repo=saphira
url=https://github.com/intel/msr-tools
# Upstream tags carry the msr-tools- prefix.
source=https://github.com/intel/msr-tools/archive/refs/tags/msr-tools-${pkgver}.tar.gz
sha256=9b87245ee091a798184e447066e9e0d7709b7c81f5e6ad55f2b958c1aa50c4a3

# No runtime deps beyond libc. Needs the msr kernel module + /dev/cpu
# nodes at runtime, same as upstream.
depends=""
# x86 MSRs do not exist elsewhere: fail closed off x86_64 (established
# SAPHIRA_ARCH case pattern) rather than shipping dead binaries.
# Upstream install target ignores DESTDIR, so install manually.
makedepends="binutils gcc make saphira-kernel-headers"

recipe_build() {
	case "${SAPHIRA_ARCH:-x86_64}" in
		x86_64) ;;
		*) echo "ERROR: msr-tools is x86_64-only (x86 MSRs): ${SAPHIRA_ARCH:-x86_64}" >&2; return 1 ;;
	esac
	MSR_BALL="$RECIPE_DIR/files/msr-tools-${pkgver}.tar.gz"
	echo "$sha256  $MSR_BALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$MSR_BALL"
	make -C "$SRC" -j${JOBS:-$(nproc)} CC=gcc
}

recipe_install() {
	for tool in rdmsr wrmsr cpuid; do
		install -D -m 0755 "$SRC/$tool" "$PKGDEST/usr/sbin/$tool"
	done
}

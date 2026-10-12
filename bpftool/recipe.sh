#!/bin/sh

pkgname=bpftool
pkgver=7.2.2
pkgrel=1
# LEGACY IDENTITY, DISABLED: superseded by per-$kver saphira-bpftool-*
# recipes. Stays only as reference; must never build or publish again.
disabled=yes
disabled_reason='superseded by per-kver saphira-bpftool-7.1.5/-7.2.2/-7.2.3/-7.3-rc1 (independently available identities)'
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='BPF tool for kernel 7.2.2 (BTF dump, program/map/link inspection, gen skeleton)'
license=GPL-2.0-only
origin=bpftool
repo=saphira
url=https://github.com/torvalds/linux
# Built from the SAME vendored kernel source saphira-kernel builds, not
# from a separate fetch, and not from a standalone bpftool tarball --
# because upstream ships no such tarball: bpftool lives in the kernel
# tree at tools/bpf/bpftool.
#
# Reusing the kernel archive is deliberate on three counts:
#
#   1. bpftool parses the kernel's own BTF, so a version match is a
#      correctness property, not a convenience. A bpftool from a
#      different kernel generation is a tool that may not read the BTF it
#      is pointed at.
#   2. The archive is already vendored and already pinned. Duplicating
#      ~140MB of identical bytes under a second package would double the
#      supply-chain surface for no new capability.
#   3. It stays buildable offline. The repo's rule is that a recipe which
#      downloads upstream source must also vendor the verified archive;
#      pointing at the already-vendored, already-verified archive
#      satisfies that without a second copy.
#
# The package is version-locked to the kernel by pkgver, which IS the
# kernel version, so the NVR reads bpftool-7.2.2-r1. That is deliberate:
# a new kernel means a new bpftool, exactly as it means a new kmod set, and
# an NVR that carries the kernel version makes the pairing impossible to
# miss. It also follows saphira-kernel-headers, the closest sibling, which
# carries the kernel version in pkgver. Naming it bpftool-7.2.2 instead
# produced the doubled NVR bpftool-7.2.2-7.2.2-r1, because bpftool has no
# upstream version separate from the kernel it is cut from.
#
# New kernel: copy this recipe and set the pkgname and pkgver.
#
# Note the recipe version IS the kernel version: the package builds from
# the kernel source of the same version, and pkgver=7.2.2 is therefore the
# single source of truth for both, not a second copy of the same number.
#
# Nothing here may reference $RECIPE_DIR at the top level. The resolver
# sources this file to read metadata, and RECIPE_DIR only exists inside
# the build functions, so a top-level use of it aborts dependency
# resolution with "RECIPE_DIR: unbound variable" before any build starts.
# The archive path is therefore resolved inside recipe_build.

depends="elfutils zlib"
# bison and flex are needed to build the Kconfig parser, which
# `make olddefconfig` runs. saphira-kernel carries the same two for the
# same reason; without bison the build stops at
# scripts/Makefile.host:17: bison: command not found.
makedepends="bison elfutils-dev flex gcc make openssl-dev pkgconf zlib-dev saphira-kernel-headers"

recipe_build()
{
	KBALL="$RECIPE_DIR/../saphira-kernel/files/linux-${pkgver}.tar.xz"
	[ -f "$KBALL" ] || {
		echo "ERROR: kernel source archive not found: $KBALL" >&2
		echo "       bpftool is built from the kernel tree; the archive is" >&2
		echo "       vendored by saphira-kernel. See the header comment." >&2
		return 1
	}
	# Verify before unpacking, not after. The hash comes from the sidecar
	# beside the archive rather than from grepping saphira-kernel's
	# recipe: that recipe selects its sha256 with a `case "$pkgver" in'
	# block, so the assignments are tab-indented and one-per-version, and
	# a naive `^sha256=' extraction finds either nothing or the wrong
	# version's hash. The sidecar is per-archive, so there is no version
	# to get wrong, and saphira-packager/tests/supply-chain.sh already
	# guarantees every consumed archive has one that verifies and whose
	# bytes match the hash the owning recipe declares upstream.
	[ -f "$KBALL.sha256" ] || {
		echo "ERROR: no sidecar for the kernel archive: $KBALL.sha256" >&2
		return 1
	}
	(cd "$(dirname "$KBALL")" && sha256sum -c "$(basename "$KBALL").sha256") || {
		echo "ERROR: kernel archive does not match its sidecar: $KBALL" >&2
		return 1
	}

	mkdir -p "$SRC/linux-${pkgver}"
	tar --no-same-owner -C "$SRC/linux-${pkgver}" --strip-components=1 -xf "$KBALL"
	cd "$SRC/linux-${pkgver}" || return 1

	# The tools build reads the kernel configuration; it does not need a
	# compiled kernel. Resolving the config here rather than relying on
	# the archive's defaults keeps the tool in step with the kernel it
	# will be pointed at.
	cp "$RECIPE_DIR/../saphira-kernel/files/config-${pkgver}-akadata" .config || return 1
	make olddefconfig || return 1

	# Build only bpftool. "make tools" would also build perf and the rest
	# of the userspace tools, none of which this package ships.
	make tools/bpf/bpftool || return 1
}

recipe_install()
{
	# /usr/sbin is not an arbitrary choice: systemd's meson build looks
	# for bpftool on PATH and then at /usr/sbin/bpftool specifically
	# (src/bpf/meson.build). This is where the BPF framework finds it.
	install -D -m 0755 "$SRC/linux-${pkgver}/tools/bpf/bpftool/bpftool" \
		"$PKGDEST/usr/sbin/bpftool"
	install -D -m 0644 "$SRC/linux-${pkgver}/Documentation/bpftool/bpftool.rst" \
		"$PKGDEST/usr/share/doc/bpftool/bpftool.rst" 2>/dev/null || :
}

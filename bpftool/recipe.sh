#!/bin/sh

pkgname=bpftool
pkgver=7.1.5
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='BPF tool (BTF dump, program/map/link inspection, gen skeleton)'
license='GPL-2.0-only'
origin=bpftool
repo=saphira
url=https://github.com/torvalds/linux
# Built from the SAME vendored kernel source saphira-kernel-7.1.5
# builds, not from a separate fetch, and not from a standalone
# bpftool tarball -- because upstream ships no such tarball:
# bpftool lives in the kernel tree at tools/bpf/bpftool.
#
# Reusing the kernel archive is deliberate on three counts:
#
#   1. The archive is already vendored and already pinned. Duplicating
#      ~140MB of identical bytes under a second package would double the
#      supply-chain surface for no new capability.
#   2. It stays buildable offline. The repo's rule is that a recipe which
#      downloads upstream source must also vendor the verified archive;
#      pointing at the already-vendored, already-verified archive
#      satisfies that without a second copy.
#   3. The tool does not depend on the version of the running kernel.
#      This reverses the per-kernel identity doctrine (operator decision
#      2026-10-19, retiring saphira-bpftool-*: one identity was split
#      into four per-kver packages in commit a3fd226d, each owning the
#      same /usr/sbin/bpftool path, so no two could ever co-install
#      and every staged transaction collided at publication). bpftool
#      is a BTF *reader*; it is built once, natively for musl, from the
#      7.1.5 tree, and stays valid across kernel generations.
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
# saphira-linux-uapi-headers supplies host UAPI (single active line,
# no version pin: the name is the selection); the in-tree olddefconfig
# below generates the versioned headers locally at build time.
makedepends="bison elfutils-dev flex gcc make openssl-dev pkgconf zlib-dev saphira-linux-uapi-headers"

recipe_build()
{
	KBALL="$RECIPE_DIR/../saphira-kernel-7.1.5/files/linux-7.1.5.tar.xz"
	[ -f "$KBALL" ] || {
		echo "ERROR: kernel source archive not found: $KBALL" >&2
		echo "       bpftool is built from the kernel tree; the archive is" >&2
		echo "       vendored by saphira-kernel-7.1.5. See the header comment." >&2
		return 1
	}
	# Verify before unpacking, not after. The hash comes from the sidecar
	# beside the archive rather than from grepping the kernel recipe.
	# The sidecar is per-archive, so there is no version to get wrong,
	# and saphira-packager/tests/supply-chain.sh already guarantees every
	# consumed archive has one that verifies and whose bytes match the
	# hash the owning recipe declares upstream.
	[ -f "$KBALL.sha256" ] || {
		echo "ERROR: no sidecar for the kernel archive: $KBALL.sha256" >&2
		return 1
	}
	(cd "$(dirname "$KBALL")" && sha256sum -c "$(basename "$KBALL").sha256") || {
		echo "ERROR: kernel archive does not match its sidecar: $KBALL" >&2
		return 1
	}

	mkdir -p "$SRC/linux-7.1.5"
	tar --no-same-owner -C "$SRC/linux-7.1.5" --strip-components=1 -xf "$KBALL"
	cd "$SRC/linux-7.1.5" || return 1

	# The tools build reads the kernel configuration; it does not need a
	# compiled kernel. Resolving the config here rather than relying on
	# the archive's defaults keeps the build reproducible.
	cp "$RECIPE_DIR/../saphira-kernel-7.1.5/files/config-7.1.5-akadata" .config || return 1
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
	# Sole owner of this path: the per-kernel saphira-bpftool-*
	# identities are retired precisely because they collided here.
	install -D -m 0755 "$SRC/linux-7.1.5/tools/bpf/bpftool/bpftool" \
		"$PKGDEST/usr/sbin/bpftool"
	install -D -m 0644 "$SRC/linux-7.1.5/Documentation/bpftool/bpftool.rst" \
		"$PKGDEST/usr/share/doc/bpftool/bpftool.rst" 2>/dev/null || :
}

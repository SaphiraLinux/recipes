#!/bin/sh

pkgname=nvidia-container-toolkit
pkgver=1.20.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='NVIDIA container toolkit (ctk CLI, runtime wrappers, CDI hook)'
license='Apache-2.0'
origin=nvidia-container-toolkit
repo=saphira
url=https://github.com/NVIDIA/nvidia-container-toolkit
source=https://github.com/NVIDIA/nvidia-container-toolkit/archive/refs/tags/v${pkgver}.tar.gz
sha256=1c5b0f17bd3f56f3d1faa0ddaba8fa0c606fc416aeaf0ee0953265a438fab647
# r1: initial native port, matched to containerd 2.4.2 + libnvidia-container
# 1.20.1 (the three release in lockstep).
# Musl binaries with CGO enabled: the NVML device-discovery path
# (vendored go-nvml/pkg/dl, a dlopen wrapper with no !cgo stub, plus the
# nvsandboxutils C calls) fundamentally requires cgo, so CGO_ENABLED=1
# with musl gcc (same answer as runc's seccomp). The result links musl
# libc dynamically — verified by the INTERP proof below. Vendor tree is
# shipped (hermetic, no downloads).
# Binaries (mirroring upstream packaging, minus the installer):
# nvidia-ctk, nvidia-container-runtime, nvidia-container-runtime-hook,
# nvidia-cdi-hook, nvidia-container-runtime.cdi,
# nvidia-container-runtime.legacy. nvidia-ctk-installer is omitted: it
# copies binaries into foreign host layouts (CoreOS-style), which has no
# meaning on Saphira.
# No config file shipped: /etc/nvidia-container-runtime/config.toml is
# generated on the GPU host by `nvidia-ctk runtime configure
# --runtime=containerd` (upstream flow). No init units in r1: the only
# units upstream ships are nvidia-cdi-refresh service+path, a
# device-triggered oneshot with no OpenRC .path equivalent and no GPU to
# validate trigger behavior against — deferred with this note, not
# silently dropped.
# depends=libnvidia-container (the hook/ctk drive nvidia-container-cli at
# runtime) + containerd (the runtime being wrapped).

depends="libnvidia-container containerd"
makedepends="go gcc"

recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/v$pkgver.tar.gz" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/v$pkgver.tar.gz"
	patch -d "$SRC" -Np1 -i "$RECIPE_DIR/files/0001-musl-go-nvml.patch"
	mkdir -p "$BUILDDIR"
	export GOCACHE="$BUILDDIR/.gocache" GOPATH="$BUILDDIR/.gopath"
	export GOFLAGS=-mod=vendor CGO_ENABLED=1 GOTOOLCHAIN=local GOAMD64=v3
	export CC=gcc
	cd "$SRC"
	for cmd in nvidia-ctk nvidia-container-runtime nvidia-container-runtime-hook nvidia-cdi-hook nvidia-container-runtime.cdi nvidia-container-runtime.legacy; do
		go build -trimpath \
			-ldflags="-buildid= -s -w -X github.com/NVIDIA/nvidia-container-toolkit/internal/info.version=$pkgver" \
			-o "$BUILDDIR/$cmd" "./cmd/$cmd"
	done
	# musl binds eagerly: the NVML symbols go-nvml deliberately leaves
	# unresolved at link (resolved at runtime via dlopen) must EXIST for
	# the binary to start at all. glibc's lazy binding hides this; musl
	# does not. Build a stub libnvidia-ml.so.1 for build-tree proofs ONLY
	# (never shipped; mirrors NVIDIA's own stub practice). The real driver
	# lib is a GPU-host runtime concern. Consequence, stated plainly: on
	# musl the toolkit binaries start only where the driver lib exists.
	STUBDIR="$BUILDDIR/stub"; mkdir -p "$STUBDIR"
	nm -D --undefined-only "$BUILDDIR/nvidia-ctk" | awk '$1=="U"{print $2}' |
		cut -d@ -f1 | sort -u | grep -E "^(nvml|nvSandboxUtils)" |
		while read -r sym; do printf 'void %s(void){}\n' "$sym"; done > "$STUBDIR/stub.c"
	gcc -shared -o "$STUBDIR/libnvidia-ml.so.1" "$STUBDIR/stub.c" ||
		{ echo "ERROR: NVML stub build failed" >&2; return 1; }
	# Proofs (hardware-independent): all six binaries exist and are
	# executable; ctk identifies itself under the stub (its --version path
	# never calls NVML). Deeper CLI runs need the real driver: pending
	# hardware. NOTE: LD_PRELOAD, not LD_LIBRARY_PATH — the binary carries
	# no DT_NEEDED for libnvidia-ml (path only helps locate NEEDED libs);
	# preloading is what puts the stub's symbols in the search scope.
	for cmd in nvidia-ctk nvidia-container-runtime nvidia-container-runtime-hook nvidia-cdi-hook nvidia-container-runtime.cdi nvidia-container-runtime.legacy; do
		[ -x "$BUILDDIR/$cmd" ] ||
			{ echo "ERROR: missing binary $cmd" >&2; return 1; }
	done
	LD_PRELOAD="$STUBDIR/libnvidia-ml.so.1" "$BUILDDIR/nvidia-ctk" --version | grep -q "$pkgver" ||
		{ echo "ERROR: nvidia-ctk version proof failed" >&2; return 1; }
	# Musl-cgo proof: the loader must be musl, not glibc.
	command -v readelf || echo "note: no readelf in worker"
	readelf -l "$BUILDDIR/nvidia-ctk" > "$BUILDDIR/interp.txt" 2>&1
	grep -q "ld-musl" "$BUILDDIR/interp.txt" ||
		{ cat "$BUILDDIR/interp.txt"; echo "ERROR: nvidia-ctk musl INTERP proof failed" >&2; return 1; }
}

recipe_install()
{
	for cmd in nvidia-ctk nvidia-container-runtime nvidia-container-runtime-hook nvidia-cdi-hook nvidia-container-runtime.cdi nvidia-container-runtime.legacy; do
		install -D -m 0755 "$BUILDDIR/$cmd" "$PKGDEST/usr/bin/$cmd"
	done
}

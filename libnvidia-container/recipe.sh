#!/bin/sh

pkgname=libnvidia-container
pkgver=1.20.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='NVIDIA container library + nvidia-container-cli (no driver blobs)'
license='Apache-2.0'
origin=libnvidia-container
repo=saphira
url=https://github.com/NVIDIA/libnvidia-container
source=https://github.com/NVIDIA/libnvidia-container/archive/refs/tags/v${pkgver}.tar.gz
sha256=e9ce8e6e69638e45c44f6b31e9e88bdff70b4a178a13f27b7f22425d208aa6ec
# r1: initial native port (Phase 2 of the container stack).
# CUDA posture: ON but OPTIONAL, and musl-native. This recipe builds ONLY
# the open container library and CLI from source. It deliberately does NOT
# vendor, download, or link the proprietary driver userspace
# (libcuda/libnvidia-ml from the .run installer): those are dlopened at
# RUNTIME and belong inside the GPU VM / containers, never in the Saphira
# host payload and never as a build input. No glibc enters the dependency
# closure (makedepends are all native musl packages).
# Feature audit: WITH_SECCOMP=yes (system libseccomp), WITH_LIBELF=yes
# (system elfutils -lelf, no download). WITH_TIRPC is inverted from what
# its name suggests: yes builds a BUNDLED libtirpc-1.3.2 downloaded from
# sourceforge at build time (fragile, duplicates system 1.3.7), so we pass
# no and supply the system libtirpc (1.3.7, published) manually via
# CPPFLAGS (-DWITH_TIRPC for rpc.h, -isystem for the headers) and LDLIBS
# (-ltirpc; WITH_TIRPC unset would mean glibc SunRPC, absent on musl).
# WITH_NVCGO stays at the upstream default (yes): the nvcgo Go bindings
# build hermetically from their own vendor tree (hence go in makedepends).
# Saphira adaptations: LDCONFIG=true (musl has no ldconfig),
# libdbgdir discarded (Saphira ships stripped, no debug-split convention;
# the shipped .so is already stripped by upstream rules), LIB_VERSION set
# explicitly (no git in the worker for version inference), REVISION set to
# the true upstream v1.20.1 commit (annotated tag object d58149f... ->
# 3e428194f8616a81e16834d27365e4a663668533; mk/common.mk refuses empty).
# musl audit: only the CLI uses argp.h (musl has no argp) — linked from
# system argp-standalone (static libargp.a) via LDLIBS. The library itself
# is argp-free.
# No daemon, no init units (library + CLI only). Hardware tests
# (nvidia-container-cli info) need a GPU host: pending hardware.

depends="libcap elfutils libtirpc libseccomp"
makedepends="gcc make pkgconf go rpcsvc-proto argp-standalone-dev elfutils-dev libcap-dev libtirpc-dev libseccomp-dev"

recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/v$pkgver.tar.gz" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/v$pkgver.tar.gz"
	patch -d "$SRC" -Np1 -i "$RECIPE_DIR/files/0001-musl-compat.patch"
	mkdir -p "$BUILDDIR/dbg-discard"
	export GOCACHE="$BUILDDIR/.gocache" GOPATH="$BUILDDIR/.gopath"
	export GOTOOLCHAIN=local GOAMD64=v3
	cd "$SRC"
	make -j${JOBS:-$(nproc)} LIB_VERSION=$pkgver REVISION=3e428194f8616a81e16834d27365e4a663668533 \
		WITH_LIBELF=yes WITH_TIRPC=no WITH_SECCOMP=yes \
		CPPFLAGS="-D_GNU_SOURCE -D_FORTIFY_SOURCE=2 -DNDEBUG -DNV_LINUX -isystem /usr/include/tirpc -DWITH_TIRPC" \
		LDLIBS="-l:libargp.a -ltirpc -lpthread" \
		LDCONFIG=true libdbgdir="$BUILDDIR/dbg-discard"
	# Proofs (hardware-independent): the CLI runs and identifies itself.
	# LD_LIBRARY_PATH pins the just-built .so: the link-time rpath
	# ($ORIGIN/../$LIB) only resolves after installation into prefix,
	# and the .so.1 SONAME symlink is likewise created at install time,
	# so both are staged here in the (disposable) build tree.
	ln -sf "libnvidia-container.so.$pkgver" libnvidia-container.so.1
	LD_LIBRARY_PATH="$SRC" ./nvidia-container-cli --version | grep -q "$pkgver" ||
		{ echo "ERROR: nvidia-container-cli version proof failed" >&2; return 1; }
	if readelf -d libnvidia-container.so.$pkgver | grep -qE "libcuda|libnvidia-ml"; then
		echo "ERROR: driver userspace leaked into link" >&2; return 1
	fi
}

recipe_install()
{
	cd "$SRC"
	make DESTDIR="$PKGDEST" prefix=/usr libdir=/usr/lib \
		LIB_VERSION=$pkgver REVISION=3e428194f8616a81e16834d27365e4a663668533 \
		WITH_LIBELF=yes WITH_TIRPC=no WITH_SECCOMP=yes \
		LDLIBS="-l:libargp.a -ltirpc -lpthread" \
		LDCONFIG=true libdbgdir="$BUILDDIR/dbg-discard" install
	# Upstream unconditionally installs the detached .debug file; with the
	# discard dir above it lands under $PKGDEST$BUILDDIR, which must not
	# ship. Remove it so the payload holds only the stripped library.
	case $BUILDDIR in ""|/) echo "ERROR: refusing to prune empty BUILDDIR" >&2; return 1 ;; esac
	rm -rf "$PKGDEST$BUILDDIR"
	# Upstream relies on ldconfig to create the SONAME symlinks
	# (.so.1 -> .so.1.20.1); musl Saphira has no ldconfig, so without
	# these the shipped .so -> .so.1 link dangles and the CLI cannot
	# load the library. Create them explicitly.
	ln -sf libnvidia-container.so.$pkgver "$PKGDEST/usr/lib/libnvidia-container.so.1"
	ln -sf libnvidia-container-go.so.$pkgver "$PKGDEST/usr/lib/libnvidia-container-go.so.1"
	# The .pc advertises the skipped ldconfig path; harmless on musl.
}

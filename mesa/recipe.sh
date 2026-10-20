#!/bin/sh
pkgname=mesa
pkgver=26.2.5
pkgrel=3
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Mesa 3D (headless EGL surfaceless + GBM, desktop OpenGL, no X11/Wayland)'
license='MIT'
origin=mesa
repo=saphira
url=https://www.mesa3d.org/
source=https://archive.mesa3d.org/mesa-26.2.5.tar.xz
sha256=794b3d1729075dae7ebd47c7283b7ca0cdb5dec668f7f11cc0a5d82f6138a0a5

# Headless EGL/GBM build. No X11/Wayland libraries exist in Saphira,
# so platforms=auto resolves to no window system; egl-native-platform
# is pinned to surfaceless (the EGL default for a headless server -
# QEMU egl-headless selects its platform explicitly anyway).
# Gallium drivers: swrast (llvmpipe/softpipe universal software
# fallback), nouveau, iris, crocus, r600, r300, i915, freedreno,
# etnaviv, lima, panfrost, tegra, v3d, vc4. Old hardware is not a
# removal justification: r300/i915 build with the in-tree LLVM draw
# path and ship here. Guest-side drivers (virgl, svga, d3d12) stay
# out - they belong inside guests, not on the host. radeonsi is out
# ONLY because mesa hard-requires the LLVM amdgpu module for it
# (proven by the r1 build failure: "modules: amdgpu(missing)") and
# Saphira's LLVM builds X86+BPF only; rebuilding LLVM with AMDGPU
# ripples into clang, so that is a filed toolchain task, not a
# permanent cut - radeonsi returns the moment it lands.
# Vulkan drivers: swrast (lavapipe), intel, intel_hasvk, broadcom,
# freedreno, panfrost, imagination, nouveau - all buildable against
# the packaged vulkan-headers with no LLVM target gaps. amd needs the
# same LLVM amdgpu module (same task as radeonsi). virtio+gfxstream
# belong to the rutabaga follow-up; microsoft-experimental is
# Windows-only; kosmikrisp is unevaluated. The Vulkan loader itself
# is a follow-up (drivers ship and probe without it).
# html-docs enabled via the in-tree Sphinx 9.1.0 + hawkmoth 0.22.0
# toolchain (mesa hard-requires hawkmoth>=0.16.0 for the docs build).
# The graphviz dot binary is absent: sphinx skips rendering diagrams
# with a logged warning (mesa passes -W only under its werror option,
# which stays off), so docs ship complete except generated figures -
# packaging dot (graphviz chain, needs its own headless evaluation)
# is a filed follow-up that will fill them in. Not a silent cut: the
# gap is visible in the build log and tracked.
# Tests: mesa's own suite needs /dev/dri render nodes absent from the
# isolated builder, so no test target runs - documented genuine
# limitation, not convenience (same reason libdrm/virglrenderer/
# libepoxy tests stay off; python modules carry import smoke tests
# where the builder permits).
depends="libdrm expat zlib zstd llvm libunwind udev elfutils libarchive libxml2"
makedepends="
	binutils
	bison
	flex
	gcc
	meson
	ninja
	pkgconf
	python3
	python-mako
	python-pycparser
	python-clang
	pyyaml
	packaging
	python-sphinx
	python-hawkmoth
	glslang
	rustc
	bindgen
	cbindgen
	spirv-llvm-translator
	spirv-tools
	clang
	expat
	expat-dev
	elfutils
	elfutils-dev
	libarchive
	libarchive-dev
	libxml2
	libxml2-dev
	libdrm
	libdrm-dev
	llvm
	zlib
	zlib-dev
	zstd
	zstd-dev
	lz4-dev
	xz-dev
	openssl-dev
	bzip2-dev
	libunwind
	libunwind-dev
	udev
	udev-dev
	vulkan-headers
"

subpackages="$pkgname-dev $pkgname-doc"

# freedreno decode tools declare dependency('libarchive',
# allow_fallback: true) and mesa ships libarchive/libxml2 .wrap
# fallbacks. r1 proved the failure mode: without the native -dev
# packages meson silently builds AND INSTALLS those subprojects, so
# foreign bsdtar/xmllint binaries and .so files land in mesa's payload
# (INSTALL failure: mesa overwrote usr/bin/xmllint owned by libxml2).
# r2 proved the subtle second half: the native .pc is NOT enough.
# meson link-tests the probe, and libarchive.so.19's DT_NEEDED
# (liblz4/liblzma/libcrypto/libbz2) must all resolve in the sysroot,
# so lz4-dev/xz-dev/openssl-dev/bzip2-dev ride along purely to satisfy
# the probe - Saphira's libxml2 needed nothing extra only because it
# builds --without-lzma. (Global --wrap-mode=nofallback was considered
# and REJECTED: src/compiler/rust consumes the syn crate via
# dependency(fallback:) for NVK, and nofallback would kill it.)
# Never remove these without checking subprojects/*.wrap first.
recipe_build()
{
	# LLVM is built without RTTI, so Mesa must match it (mesa's own
	# error message prescribes -Dcpp_rtti=false). This tracks the
	# toolchain, it is not a Mesa feature cut.
	# Rust bindgen support needs four crates (syn, unicode-ident,
	# quote, proc-macro2) pinned by subprojects/*.wrap. Meson would
	# fetch them from crates.io at configure time; instead serve the
	# vendored archives from files/ via the package cache (hashes
	# match the wrap pins, verified by fetch-vendor-sources style
	# sidecars). If upstream bumps a wrap pin, vendor the new
	# archive the same way.
	mkdir -p "$BUILDDIR/meson-cache"
	for crate in syn-2.0.87 unicode-ident-1.0.12 quote-1.0.35 proc-macro2-1.0.86; do
		cp "$RECIPE_DIR/files/$crate.tar.gz" "$BUILDDIR/meson-cache/"
	done
	export MESON_PACKAGE_CACHE_DIR="$BUILDDIR/meson-cache"
	# NVK (nouveau Vulkan) is ON: bindgen 0.72.1 is packaged natively
	# (libunwind-dev link fix) and spirv-llvm-translator 22.1.x
	# satisfies mesa's CLC hard requirement (>=chosen-LLVM 22.1,
	# <22.2). Nouveau OpenGL (gallium) was never affected.
	# NOTE: no comment lines inside the \-continued command
	# below: a # comment terminates the continuation and silently drops
	# every following -D flag (that exact mistake broke GLX handling).
	meson setup build "$SRC" \
		--prefix=/usr \
		-Dlibdir=lib \
		-Dplatforms= \
		-Degl-native-platform=surfaceless \
		-Dgallium-drivers=softpipe,llvmpipe,r300,i915,r600,nouveau,iris,crocus,freedreno,etnaviv,lima,panfrost,tegra,v3d,vc4 \
		-Dvulkan-drivers=swrast,intel,intel_hasvk,broadcom,freedreno,panfrost,imagination,nouveau \
		-Dopengl=true -Dgles1=enabled -Dgles2=enabled \
		-Degl=enabled -Dgbm=enabled -Dglx=disabled -Dglvnd=disabled \
		-Dllvm=enabled -Dshared-llvm=enabled \
		-Dcpp_rtti=false \
		-Ddraw-use-llvm=true -Damd-use-llvm=false \
		-Dzstd=enabled -Dzlib=enabled -Dlibunwind=enabled \
		-Dvideo-codecs=all_free -Dhtml-docs=enabled
	meson compile -C build
}

recipe_install()
{
	DESTDIR="$PKGDEST" meson install -C build
}

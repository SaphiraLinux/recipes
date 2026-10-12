pkgname=ndctl
pkgver=85
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='NVDIMM control tool (create/list/configure pmem and dax namespaces)'
license=GPL-2.0-only
origin=ndctl
repo=main
url=https://github.com/pmem/ndctl
# Runtime closure for the shipped binaries/libs (RUNTIME evaluate stage):
# ndctl/daxctl need json-c + iniparser; libcxl needs kmod + udev.
# (uuid comes with the base closure.)
depends="iniparser json-c kmod udev"
# codeload snapshot tarball (upstream publishes no release assets);
# basename is the tag, pinned by sha256 like any other vendor archive.
vendor=https://codeload.github.com/pmem/ndctl/tar.gz/refs/tags/v85
sha256=69039ee12c75c44f67b5fa3f1abb61d1c38ff9303021e50cec0b45801cc93b2e

makedepends="
	binutils
	gcc
	iniparser-dev
	json-c-dev
	kmod-dev
	make
	meson
	ninja
	pkgconf
	udev-dev
	util-linux-dev
	xz-dev
	zlib-dev
	zstd-dev
"

recipe_build()
{
	meson setup "$BUILDDIR" "$SRC" \
		--prefix=/usr \
		--libdir=/usr/lib \
		-Dversion-tag=v85 \
		-Ddocs=disabled \
		-Dasciidoctor=disabled \
		-Dlibtracefs=disabled \
		-Dsystemd=disabled \
		-Dkeyutils=disabled \
		-Dtest=disabled \
		-Ddestructive=disabled
 # Disabled features and why (all recorded, revisit deliberately):
 # docs/asciidoctor: doc toolchain absent from the universe.
 # libtracefs: trace tooling absent.
 # systemd: ndctl-monitor daemon integration; unneeded for the namespace
 #   test operations this package exists for.
 # keyutils: NVDIMM passphrase management only; disabled because ndctl
 #   probes it with a plain cc.find_library() call and the worker
 #   toolchain does not resolve non-pkgconf -l lookups
 #   (ld: cannot find -lkeyutils). Revisit with a pkgconf-based probe
 #   or toolchain search-path fix if passphrase support is ever wanted.
 # test/destructive: suites not shipped.
	ninja -C "$BUILDDIR"
}

recipe_install()
{
	DESTDIR="$PKGDEST" ninja -C "$BUILDDIR" install
}

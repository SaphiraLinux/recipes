#!/bin/sh

pkgname=rpm
pkgver=6.1.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='RPM package manager tools (rpm, rpmbuild, rpm2cpio)'
license='GPL-2.0-or-later'
origin=rpm
repo=saphira
url=https://rpm.org/
source=https://github.com/rpm-software-management/rpm/releases/download/rpm-6.1.0-release/rpm-6.1.0.tar.bz2
sha256=f520810d27c74bf1c5d8b8885845c61e0c845f62d33e68b02e020633a8b62fe3
# Provenance: upstream publishes no hash for this release asset (the
# CHECKSUM file alongside it is empty). Hash recorded from the
# TLS-verified official release download and verified by clean
# extraction; it pins the vendored bytes for every future fetch.
# No musl patches required (attempt clean first; Alpine's rpm needs
# only glibc-specific patches, inapplicable here).
# Feature scope is packaging tooling only:
# - OpenPGP via OpenSSL, not Sequoia (no Rust toolchain needed for
#   unsigned test builds; matches Alpine's choice).
# - No SELinux/audit/fapolicyd/dbus (no userspace for them here,
#   and MAC-adjacent machinery is out of scope).
# - No Python bindings (tooling only).
# - No plugins (dbus plugin unneeded without dbus).
# - No testsuite (needs containers, like upstream/Alpine).
# Kept at defaults: sqlite+ndb backends, NLS, OpenMP, capabilities,
# ACLs, readline, bzip2, iconv, zstd, libdw, libelf, liblzma.
# The brp helper scripts live in main (only -dev/-doc/-libs splits
# exist), hence bash+perl runtime dependencies.
# readline is also off: only the interactive query CLI uses it,
# and its .pc chain demands a termcap provider nothing here
# ships. Nothing in the packaging path needs line editing.
# libseccomp and musl-fts ride along transitively (libmagic and
# libdw need them at link and run time); declared explicitly here
# because the file/elfutils recipes do not carry those edges
# themselves (separate latent findings, not fixed in this task).
depends="bash perl libarchive openssl sqlite file libcap acl elfutils popt zlib bzip2 xz zstd gettext libseccomp musl-fts"
# Lua comes from the existing lua54 recipe (5.4.8 satisfies
# >= 5.2): an earlier revision of this task added a duplicate
# bare `lua` 5.4.9 recipe which collided file-for-file with the
# published lua54 at sign time. Removed; lua54-dev carries the
# same PIC static objects rpm links.
makedepends="gcc make cmake ninja pkgconf scdoc gawk gettext perl bash binutils file lua54-dev sqlite-dev libarchive-dev popt-dev openssl-dev file-dev libcap-dev acl-dev elfutils-dev zlib-dev bzip2-dev xz-dev zstd-dev libseccomp-dev musl-fts-dev"
subpackages="$pkgname-dev $pkgname-doc"

recipe_build()
{
	cd "$SRC"
	# musl has no GLOB_BRACE (verified against musl glob.h, which
	# carries GLOB_TILDE but not BRACE): degrade to no-op.
	patch -p1 -d "$SRC" < "$RECIPE_DIR/files/rpm-musl-glob.patch"
	cmake -B build -G Ninja \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DCMAKE_INSTALL_SYSCONFDIR=/etc \
		-DCMAKE_BUILD_TYPE=MinSizeRel \
		-DENABLE_PYTHON=OFF \
		-DENABLE_PLUGINS=OFF \
		-DENABLE_TESTSUITE=OFF \
		-DWITH_SEQUOIA=OFF \
		-DWITH_OPENSSL=ON \
		-DWITH_READLINE=OFF \
		-DWITH_SELINUX=OFF \
		-DWITH_AUDIT=OFF \
		-DWITH_FAPOLICYD=OFF \
		-DWITH_DBUS=OFF
	cmake --build build -j${JOBS:-$(nproc)}
}

recipe_install()
{
	cd "$SRC"
	DESTDIR="$PKGDEST" cmake --install build
}

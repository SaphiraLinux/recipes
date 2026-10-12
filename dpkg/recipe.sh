#!/bin/sh

pkgname=dpkg
pkgver=1.22.22
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Debian package manager tools (dpkg, dpkg-deb, dpkg-query)'
license='GPL-2.0-or-later'
origin=dpkg
repo=saphira
url=https://wiki.debian.org/Teams/Dpkg
source=https://ftp.debian.org/debian/pool/main/d/dpkg/dpkg_1.22.22.tar.xz
sha256=d5ea9f132deec8030b50ab2a02ade2b49f0c7a195805a302c8301156fe833a57
# Provenance: hash verified against the upstream .dsc
# Checksums-Sha256 record (not merely self-recorded). 1.22.x is the
# mature stable series (Alpine tracks 1.23.x; the .deb format surface
# used here is identical).
# No musl patches required: upstream builds cleanly on musl (the only
# musl-specific delta known anywhere is a test expectation about
# realpath("//"), which needs no source change).
# The fixed path-based subpackage splitter only moves headers,
# man pages and docs: dpkg installs no public headers, so there is
# no -dev split. The perl dev-tools (dpkg-scanpackages et al) live
# in /usr/bin and therefore in main, which is why perl is a runtime
# dependency, not just a build one.
depends="tar xz perl"
# Compression backends are all enabled (a .deb builder must read and
# write modern zstd-compressed data archives): zlib, bzip2, xz
# (lzma), zstd, plus libmd for digests. perl is needed for the
# -dev perl tooling (dpkg-scanpackages et al). NLS is disabled
# (matches Alpine; tooling needs no translations) so gettext is
# build-unneeded. dselect (ncurses UI) and start-stop-daemon (Debian
# init helper, not packaging tooling) are disabled by scope.
makedepends="gcc make pkgconf perl zlib-dev bzip2-dev xz-dev zstd-dev libmd-dev"
subpackages="$pkgname-doc"

recipe_build()
{
	cd "$SRC"
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--mandir=/usr/share/man \
		--localstatedir=/var \
		--with-libz \
		--with-libbz2 \
		--with-liblzma \
		--with-libzstd \
		--disable-dselect \
		--disable-start-stop-daemon \
		--disable-nls \
		--disable-static
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
	# An empty dpkg database so dpkg-query works on a fresh root
	# (debootstrap convention).
	mkdir -p "$PKGDEST/var/lib/dpkg"
	: > "$PKGDEST/var/lib/dpkg/status"
	: > "$PKGDEST/var/lib/dpkg/available"
}

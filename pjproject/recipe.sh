#!/bin/sh
pkgname=pjproject
pkgver=2.17
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Multimedia communication library (PJSIP/PJMEDIA/PJNATH stack)'
license='GPL-2.0-or-later'
origin=pjproject
repo=saphira
url=https://www.pjsip.org/
# Pinned to the exact tarball Asterisk 23.5.0 consumes from the
# asterisk/third-party mirror (its PACKAGE_URL); the in-tree .md5
# (baacc87418a95107657039269bc71538) identifies the same bytes.
source=https://raw.githubusercontent.com/asterisk/third-party/master/pjproject/2.17/pjproject-2.17.tar.bz2
sha256=04b2eb1f0f01aa0ad1945b167171843448a51aa6b7c3e806496d434f13a112b7

depends="
    gcc-libs
    openssl
    util-linux
"
depends_dev="openssl-dev util-linux-dev"

makedepends="
    binutils
    gcc
    make
    openssl-dev
    saphira-linux-uapi-headers
    util-linux-dev
"

subpackages="
    $pkgname-dev
"

recipe_build()
{
	# Proven standalone configuration (Phase 0b, musl x86_64): the four
	# generic patches Asterisk itself carries, the Asterisk config_site.h
	# tunings verbatim (ABI: PJSIP_MAX_MODULE 38, URL 512, SDP_FMT 72,
	# ICE 64, IOQUEUE 5000), minus the Asterisk allocator coupling (see
	# files/config_site.h). Feature set mirrors the proven build: no
	# sound/video (headless policy), no speex/gsm/ilbc/srtp (deps absent
	# in Saphira), matching what Asterisk consumes.
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/pjproject-2.17.tar.bz2"
	cd "$SRC"
	for p in \
		0000-configure-ssl-library-path.patch \
		0000-remove-third-party.patch \
		0010-2-17-Add-OpenSSL-version-guards.patch \
		0020-Add-PJSIP_INV_ABSORB_RETRANS_AFTER_ACK-macro-to-opt-out-of-4765.patch \
	; do
		patch -p1 < "$RECIPE_DIR/files/$p"
	done
	install -m 0644 "$RECIPE_DIR/files/config_site.h" \
		pjlib/include/pj/config_site.h
	install -m 0644 "$RECIPE_DIR/files/user.mak" user.mak
	./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--enable-shared \
		--disable-speex-codec \
		--disable-speex-aec \
		--disable-bcg729 \
		--disable-gsm-codec \
		--disable-ilbc-codec \
		--disable-l16-codec \
		--disable-g722-codec \
		--disable-g7221-codec \
		--disable-opencore-amr \
		--disable-silk \
		--disable-opus \
		--disable-video \
		--disable-v4l2 \
		--disable-sound \
		--disable-ext-sound \
		--disable-sdl \
		--disable-libyuv \
		--disable-ffmpeg \
		--disable-openh264 \
		--disable-ipp \
		--disable-libwebrtc \
		--disable-libsrtp \
		--disable-upnp \
		--without-external-pa \
		--without-external-srtp \
		--disable-resample \
		--disable-g711-codec \
		--enable-epoll
	# Upstream quirk: PJDIR must be exported or build.mak references
	# an empty path (/version.mak). Sample/test apps are built but not
	# installed; they are not run here (several need loopback audio or
	# network access the sandbox does not provide).
	export PJDIR="$SRC"
	make dep
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	cd "$SRC"
	export PJDIR="$SRC"
	DESTDIR="$PKGDEST" make install
	# asterisk_malloc_debug.h is an Asterisk-only header that redirects
	# malloc/free to Asterisk's __ast_repl_* allocators; a system library
	# must not ship it (every consumer would inherit the coupling).
	# Proven harmless: equivalent to MALLOC_DEBUG-off behaviour.
	rm -f "$PKGDEST/usr/include/pj/asterisk_malloc_debug.h"
	test ! -e "$PKGDEST/usr/include/pj/asterisk_malloc_debug.h"
	# No test/sample binaries are installed by upstream; nothing else to
	# prune. Static archives and the .pc file travel to -dev via the
	# standard split; the 12 versioned .so.2 libraries stay in main.
}

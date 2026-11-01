#!/bin/sh

pkgname=imagemagick
pkgver=7.1.2.34
# APK version maps upstream's dash to a dot: apk rejects a second
# dash, and underscore requires a trailing letter (_p3/_rc1 style),
# so 7.1.2_34 is invalid too (Debian uses the same dotted form).
# Source URL and archive keep upstream dashes.
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Image editing and conversion suite"
license="ImageMagick"
origin=imagemagick
repo=saphira
url=https://imagemagick.org/
source=https://github.com/ImageMagick/ImageMagick/releases/download/7.1.2-34/ImageMagick-7.1.2-34.tar.xz
sha256=55fe0ec246245b46c429f9e6bc65294ad4a78a66b88abd9817971ca157856323
# Provenance (verified 2026-11-01, see memoryd/saphira-build notes):
# no .asc is published; the release ships a Sigstore bundle
# (ImageMagick-7.1.2-34.intoto.jsonl). Downloaded bytes equal the
# attested subject digest; DSSE signature VERIFIED OK (openssl, proper
# PAE preimage) under the Fulcio key cert-bound to repo
# ImageMagick/ImageMagick workflow release.yml @ main (ephemeral cert
# fp 3D:12:A3:7F:..., tlog index 3254463747). Root-chain + inclusion
# proof unverified (no slsa tooling) - bounds stated, not bypassed.

depends="
    bzip2
    ghostscript
    libjpeg-turbo
    libpng
    libwebp
    libxml2
    libzip
    xz
    zlib
"

makedepends="
    binutils
    bzip2-dev
    gcc
    libjpeg-turbo-dev
    libpng
    libtool-dev
    libwebp
    libxml2
    libzip-dev
    make
    perl
    pkgconf
    xz-dev
    zlib-dev
"

recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	# jpeg/png/webp/xml/perl/zip/lzma/bzlib/Magick++ enabled (deps
	# exist); ghostscript delegate binary enabled (runtime dep).
	# freetype/tiff/x/lcms2/openjp2 stay off by headless-distribution
	# policy (ratified omissions, batch transforms only) - NOT for
	# lack of recipes.
	"$SRC/configure" --prefix=/usr --disable-static \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--with-modules --with-perl --with-magick-plus-plus=yes \
		--with-jpeg=yes --with-png=yes --with-webp=yes --with-xml=yes \
		--with-zip=yes --with-lzma=yes --with-bzlib=yes --with-gs=yes \
		--without-freetype --without-tiff --without-x \
		--without-lcms --without-openjp2
	make
}

recipe_install()
{
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
	# perllocal.pod is a per-install perl index (info/dir class):
	# nginx owns the path, so it must never ship here. find, not
	# globs: the path nests three deep.
	find "$PKGDEST" -name perllocal.pod -delete
}

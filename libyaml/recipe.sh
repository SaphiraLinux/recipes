#!/bin/sh

pkgname=libyaml
pkgver=0.2.5
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Fast YAML 1.1 parser and emitter library'
license='MIT'
origin=libyaml
repo=saphira
url=https://github.com/yaml/libyaml
source=https://github.com/yaml/libyaml/releases/download/0.2.5/yaml-0.2.5.tar.gz
sha256=c642ae9b75fee120b2d96c712538bd2cf283228d2337df2cf2988e3c02678ef4

depends=""

makedepends="
	gcc
	make
"

subpackages="$pkgname-dev"

# Ruby psych (and any future YAML consumer) needs the shared C
# parser/emitter. Verified bytes: the release tarball from
# github.com/yaml/libyaml and the pyyaml.org mirror agree
# byte-for-byte, and the MD5 matches the BLFS-published
# bb15429d8fb787e7d3f1c83ae129a999.
recipe_build()
{
	echo "$sha256  $RECIPE_DIR/files/yaml-${pkgver}.tar.gz" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 \
		-xf "$RECIPE_DIR/files/yaml-${pkgver}.tar.gz"

	cd "$SRC"

	./configure --prefix=/usr --sysconfdir=/etc --libdir=/usr/lib \
		--disable-static --localstatedir=/var
	make -j${JOBS:-$(nproc)}
	# BLFS documents make check for this package (<0.1 SBU):
	# fail closed here rather than shipping an untested parser.
	make check
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install

	find "$PKGDEST" -name '*.la' -delete

	test -f "$PKGDEST/usr/lib/libyaml-0.so.2"
	test -f "$PKGDEST/usr/include/yaml.h"
}

#!/bin/sh

pkgname=nodejs
pkgver=24.18.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Node.js JavaScript runtime (V8, npm not bundled as binary; core runtime and tools)'
license='MIT AND Apache-2.0 AND BSD-3-Clause AND ISC AND Zlib'
origin=nodejs
repo=saphira
url=https://nodejs.org/
source=https://nodejs.org/dist/v${pkgver}/node-v${pkgver}.tar.xz
sha256=86d40d594bbdfcf69009a62fdf43cb19ae72b6cb5822d2bdd8349c5a1b2fa628

# Shared system libraries (openssl, zlib) per the old-gen configuration;
# c-ares/llhttp/nghttp2 etc. build from the bundled deps. small-icu keeps
# the bundled ICU minimal (no system icu runtime dependency).
depends="openssl zlib ca-certificates"
makedepends="
	gcc
	make
	ninja
	openssl-dev
	python3
	zlib-dev
"

subpackages="$pkgname-dev $pkgname-doc"

recipe_build()
{
	./configure \
		--prefix=/usr \
		--ninja \
		--shared-openssl \
		--shared-zlib \
		--openssl-use-def-ca-store \
		--with-intl=small-icu
	ninja -C out/Release -j${JOBS:-$(nproc)}

	./out/Release/node --version | grep -q "^v${pkgver}"
	./out/Release/node -e 'console.log(21*2)' | grep -q 42
}

recipe_install()
{
	python3 tools/install.py install --dest-dir "$PKGDEST" --prefix /usr
	# Sanity: the staged runtime runs against the staged layout.
	test -x "$PKGDEST/usr/bin/node"
}

#!/bin/sh

pkgname=nodejs22
pkgver=22.23.2
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Node.js 22 LTS JavaScript runtime, side-by-side with the main nodejs (binaries suffixed: node22)'
license='MIT AND Apache-2.0 AND BSD-3-Clause AND ISC AND Zlib'
origin=nodejs22
repo=saphira
url=https://nodejs.org/
source=https://nodejs.org/dist/v${pkgver}/node-v${pkgver}.tar.xz
sha256=bbe768df8d5815d7fa76124052985332452e0a4742d39f32027550d1aab8f6fb

# Side-by-side runtime: everything is renamed away from the un-suffixed
# paths owned by the main nodejs package (node -> node22, npm -> npm22,
# corepack -> corepack22, headers -> /usr/include/node22). npm's CLI
# resolves `node` via the PATH, so npm22 runs on whichever Node runtime
# is installed; it does not require this package's own binary at runtime.
depends="openssl zlib ca-certificates"
makedepends="
	gcc
	make
	ninja
	openssl-dev
	python3
	zlib-dev
"

subpackages="$pkgname-dev"

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

	# Side-by-side renaming (the main nodejs package owns the un-suffixed
	# paths under the immutable-filename rule).
	mv "$PKGDEST/usr/bin/node" "$PKGDEST/usr/bin/node22"
	[ -e "$PKGDEST/usr/bin/npm" ] && mv "$PKGDEST/usr/bin/npm" "$PKGDEST/usr/bin/npm22"
	[ -e "$PKGDEST/usr/bin/corepack" ] && mv "$PKGDEST/usr/bin/corepack" "$PKGDEST/usr/bin/corepack22"
	[ -d "$PKGDEST/usr/lib/node_modules/npm" ] && \
		mv "$PKGDEST/usr/lib/node_modules/npm" "$PKGDEST/usr/lib/node_modules/npm22"
	[ -d "$PKGDEST/usr/lib/node_modules/corepack" ] && \
		mv "$PKGDEST/usr/lib/node_modules/corepack" "$PKGDEST/usr/lib/node_modules/corepack22"

	# Headers must not collide with nodejs-dev: relocate to node22.
	[ -d "$PKGDEST/usr/include/node" ] && \
		mv "$PKGDEST/usr/include/node" "$PKGDEST/usr/include/node22"

	# The npm/corepack bin shims are symlinks into node_modules; repoint
	# them at the renamed library directories.
	[ -e "$PKGDEST/usr/bin/npm22" ] && ln -sf ../lib/node_modules/npm22/bin/npm-cli.js \
		"$PKGDEST/usr/bin/npm22"
	[ -e "$PKGDEST/usr/lib/node_modules/corepack22" ] && [ -e "$PKGDEST/usr/bin/corepack22" ] && \
		ln -sf ../lib/node_modules/corepack22/dist/corepack.js "$PKGDEST/usr/bin/corepack22"

	test -x "$PKGDEST/usr/bin/node22"
	"$PKGDEST/usr/bin/node22" --version | grep -q "^v${pkgver}"
}

#!/bin/sh

pkgname=nodejs22
pkgver=22.23.4
# r1 (new upstream lineage): October-2026 security release (advisory
# 2026-10-21; CVEs 105481/105482/106069/106072/106073/106074/111497 -
# NOTE 105483 is 24/26-only, not applicable to this line - + c-ares
# 1.34.9, sqlite 3.53.4, undici 6.29.1, tzdata 2026e). No musl patches
# exist or are needed (upstream ships linux-x64-musl for this line).
# Bundled-vs-system: --shared-openssl/--shared-zlib link the SYSTEM
# libraries, so the advisory's bundled-OpenSSL-3.5.9 update does not
# touch our runtime linkage (proven in recipe_build + TEST); c-ares,
# llhttp, libuv, brotli, small-icu, sqlite and undici stay bundled by
# design. The eMudhra CA compromise is answered by ca-certificates
# (system trust store via --openssl-use-def-ca-store), not by Node's
# bundled NSS roots, which are inert under that flag.
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Node.js 22 LTS JavaScript runtime, side-by-side with the main nodejs (binaries suffixed: node22)'
license='MIT AND Apache-2.0 AND BSD-3-Clause AND ISC AND Zlib'
origin=nodejs22
repo=saphira
url=https://nodejs.org/
source=https://nodejs.org/dist/v${pkgver}/node-v${pkgver}.tar.xz
sha256=7b9adc82d612d0a2a863d96c46de2292552e250cee51956ebbe0146c42aacae9

# Side-by-side runtime: everything is renamed away from the un-suffixed
# paths owned by the main nodejs package (node -> node22, npm -> npm22,
# corepack -> corepack22, headers -> /usr/include/node22). npm's CLI
# resolves `node` via the PATH, so npm22 runs on whichever Node runtime
# is installed; it does not require this package's own binary at runtime.
# gcc-libs: the C++ runtime (libstdc++/libgcc_s) the node22 binary
# DT_NEEDEDs (RUNTIME-gate proven 2026-10-23, same lesson as llvm r4).
depends="openssl zlib ca-certificates gcc-libs"
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
	# layout-exception: node uses its own python configure dialect;
	# GNU dir flags do not apply. Installed paths follow the explicit
	# --prefix plus node defaults (never prefix-derived state).
	./configure \
		--prefix=/usr \
		--ninja \
		--shared-openssl \
		--shared-zlib \
		--openssl-use-def-ca-store \
		--with-intl=small-icu
	ninja -C out/Release -j${JOBS:-$(nproc)}

	[ "$(./out/Release/node --version)" = "v${pkgver}" ] || return 1
	[ "$(./out/Release/node -e 'console.log(21*2)')" = "42" ] || return 1
	# Shared-library proof: the advisory's OpenSSL/Zlib updates apply
	# to Node's BUNDLED sources, which this build does not use.
	# NOTE: no VAR=$(cmd | grep) pipes here - buildpkg-single runs
	# under `set -o pipefail` and grep -q closing the pipe early makes
	# the writer die with SIGPIPE (rc=141, r1 proven 2026-10-23).
	ldd ./out/Release/node >"$BUILDDIR/ldd.txt" || return 1
	grep -q 'libcrypto\.so' "$BUILDDIR/ldd.txt" || return 1
	grep -q 'libz\.so' "$BUILDDIR/ldd.txt" || return 1
	case "$(./out/Release/node -p 'process.versions.openssl')" in
		3.*) ;;
		*) return 1 ;;
	esac
	# October-2026 fix markers (fail closed if a future rebase drops
	# a security backport; behavior is proven by test.sh, not by these
	# greps - markers locate the patch, tests prove the behavior).
	SRC="${SRC:-.}"
	grep -q "validateStringWithoutNullBytes(name, 'name')" \
		"$SRC/lib/internal/dns/callback_resolver.js" || return 1
	grep -q "validateStringWithoutNullBytes(name, 'name')" \
		"$SRC/lib/internal/dns/promises.js" || return 1
	grep -q 'non-canonical IP address' "$SRC/lib/tls.js" || return 1
	grep -q 'BROTLI_DECODER_ERROR_FORMAT_BLOCK_SWITCH' \
		"$SRC/src/node_zlib.cc" || return 1
	grep -q 'isBuildingSnapshot' \
		"$SRC/lib/internal/crypto/random.js" || return 1
	grep -q 'probe the existence' "$SRC/lib/fs.js" || return 1
	grep -q 'hasPendingRead' "$SRC/lib/_http_agent.js" || return 1
}

recipe_install()
{
	python3 tools/install.py install --dest-dir "$PKGDEST" --prefix /usr

	# Side-by-side renaming (the main nodejs package owns the un-suffixed
	# paths under the immutable-filename rule).
	mv "$PKGDEST/usr/bin/node" "$PKGDEST/usr/bin/node22"
	[ -e "$PKGDEST/usr/bin/npm" ] && mv "$PKGDEST/usr/bin/npm" "$PKGDEST/usr/bin/npm22"
	[ -e "$PKGDEST/usr/bin/npx" ] && mv "$PKGDEST/usr/bin/npx" "$PKGDEST/usr/bin/npx22"
	[ -e "$PKGDEST/usr/bin/corepack" ] && mv "$PKGDEST/usr/bin/corepack" "$PKGDEST/usr/bin/corepack22"
	[ -d "$PKGDEST/usr/lib/node_modules/npm" ] && \
		mv "$PKGDEST/usr/lib/node_modules/npm" "$PKGDEST/usr/lib/node_modules/npm22"
	[ -d "$PKGDEST/usr/lib/node_modules/corepack" ] && \
		mv "$PKGDEST/usr/lib/node_modules/corepack" "$PKGDEST/usr/lib/node_modules/corepack22"

	# Headers must not collide with nodejs-dev: relocate to node22.
	[ -d "$PKGDEST/usr/include/node" ] && \
		mv "$PKGDEST/usr/include/node" "$PKGDEST/usr/include/node22"

	# Debugger helpers and the node(1) page live under shared paths
	# the main nodejs-doc package already owns: relocate to node22.
	[ -d "$PKGDEST/usr/share/doc/node" ] && \
		mv "$PKGDEST/usr/share/doc/node" "$PKGDEST/usr/share/doc/node22"
	[ -e "$PKGDEST/usr/share/man/man1/node.1" ] && mv "$PKGDEST/usr/share/man/man1/node.1" \
		"$PKGDEST/usr/share/man/man1/node22.1"

	# The npm/corepack bin shims are symlinks into node_modules; repoint
	# them at the renamed library directories.
	[ -e "$PKGDEST/usr/bin/npm22" ] && ln -sf ../lib/node_modules/npm22/bin/npm-cli.js \
		"$PKGDEST/usr/bin/npm22"
	[ -e "$PKGDEST/usr/lib/node_modules/npm22/bin/npx-cli.js" ] && ln -sf ../lib/node_modules/npm22/bin/npx-cli.js \
		"$PKGDEST/usr/bin/npx22"
	[ -e "$PKGDEST/usr/share/man/man1/npx.1" ] && mv "$PKGDEST/usr/share/man/man1/npx.1" \
		"$PKGDEST/usr/share/man/man1/npx22.1"
	[ -e "$PKGDEST/usr/lib/node_modules/corepack22" ] && [ -e "$PKGDEST/usr/bin/corepack22" ] && \
		ln -sf ../lib/node_modules/corepack22/dist/corepack.js "$PKGDEST/usr/bin/corepack22"

	test -x "$PKGDEST/usr/bin/node22"
	"$PKGDEST/usr/bin/node22" --version | grep -q "^v${pkgver}"
}

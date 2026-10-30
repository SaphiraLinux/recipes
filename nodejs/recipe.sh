#!/bin/sh

pkgname=nodejs
pkgver=24.22.1
pkgrel=1
# r1 (new upstream lineage): October-2026 security release (advisory
# 2026-10-21; CVEs 105481/105482/105483/106069/106072/106073/106074/
# 111497 + c-ares 1.34.9, undici 7.30.1, tzdata 2026e). No musl patches
# exist or are needed (upstream ships linux-x64-musl for this line).
# Bundled-vs-system: --shared-openssl/--shared-zlib link the SYSTEM
# libraries, so the advisory's bundled-OpenSSL-3.5.9 update does not
# touch our runtime linkage (proven in recipe_build + TEST); c-ares,
# llhttp, libuv, brotli, small-icu and undici stay bundled by design.
# The eMudhra CA compromise is answered by ca-certificates (system
# trust store via --openssl-use-def-ca-store), not by Node's bundled
# NSS roots, which are inert under that flag.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Node.js JavaScript runtime (V8, npm not bundled as binary; core runtime and tools)'
license='MIT AND Apache-2.0 AND BSD-3-Clause AND ISC AND Zlib'
origin=nodejs
repo=saphira
url=https://nodejs.org/
source=https://nodejs.org/dist/v${pkgver}/node-v${pkgver}.tar.xz
sha256=4f5379796280cdaeb0c2f358fd04b6a16cc4fb7dfa83b5a8c91a9d963b435231

# Shared system libraries (openssl, zlib) per the old-gen configuration;
# c-ares/llhttp/nghttp2 etc. build from the bundled deps. small-icu keeps
# the bundled ICU minimal (no system icu runtime dependency).
# gcc-libs: the C++ runtime (libstdc++/libgcc_s) the node binary
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

subpackages="$pkgname-dev $pkgname-doc"

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
	# greps - see the user's correction: markers locate the patch,
	# tests prove the behavior).
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
	# Sanity: the staged runtime runs against the staged layout.
	test -x "$PKGDEST/usr/bin/node"
}

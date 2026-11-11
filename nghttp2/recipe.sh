#!/bin/sh

pkgname=nghttp2
pkgver=1.70.0
pkgrel=3
# r3: split the applications (nghttp/nghttpd/nghttpx/h2load + their
# man pages) into nghttp2-apps with its own c-ares + libev edges;
# the base package is libnghttp2 only, which links neither (asserted
# below). curl's HTTP/2 needs no event loop or async DNS. HPACK debug
# tools explicitly off (would need jansson; silent autodetect is not
# a packaging decision). Payload change (files move between outputs).
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="HTTP/2 C library (nghttp2) and tools"
license="MIT"
origin=nghttp2
repo=saphira
url=https://nghttp2.org/
# Upstream moved from ngtcp2/nghttp2 to nghttp2/nghttp2; GitHub-generated
# tag archives are broken upstream - use the signed versioned release
# tarball, verified against upstream checksums.txt.
source=https://github.com/nghttp2/nghttp2/releases/download/v1.70.0/nghttp2-1.70.0.tar.gz
sha256=aa317e2cf9dca6afa0aed68f8fad6ff303ec6982e25a78c75c0b65e2b9b3ded5

depends="
    openssl
    zlib
"
subpackages="nghttp2-apps"

makedepends="
    binutils
    c-ares-dev
    gcc
    libev-dev
    make
    openssl-dev
    pkgconf
    zlib-dev
"

# Full scope: the HTTP/2 library (libnghttp2) plus the nghttpx/nghttp/
# nghttpd/h2load applications. The apps need c-ares + libev, which were
# absent from the native universe at r1 (BLOCKED_BY_c-ares,
# BLOCKED_BY_libev, lib-only build) - both packaged since, so r2 turns
# the applications on explicitly (configure fails closed if their deps
# ever go missing again instead of silently dropping them).
recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	"$SRC/configure" --prefix=/usr --sysconfdir=/etc --enable-app --disable-hpack-tools --disable-static --localstatedir=/var
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
	# Split-correctness proof: the library must not link the apps'
	# libraries (c-ares, libev); those edges belong to the
	# nghttp2-apps split alone. Asserted on the staged payload the
	# way openssh asserts its linked session binary (plain grep,
	# never -q: under the worker's pipefail, grep -q quits early
	# and the producer dies of SIGPIPE).
	for need in libcares libev; do
		if readelf -d "$PKGDEST/usr/lib/libnghttp2.so" | grep "$need" > /dev/null; then
			printf 'nghttp2: libnghttp2.so links %s (belongs in -apps only)\n' "$need" >&2
			return 1
		fi
	done
	# ... and every tool the split claims must actually be installed
	# (the splitter fails closed on missing listed paths; this names
	# them where the failure would otherwise be cryptic).
	for tool in nghttp nghttpd nghttpx h2load; do
		[ -x "$PKGDEST/usr/bin/$tool" ] || {
			printf 'nghttp2: expected tool missing: %s\n' "$tool" >&2
			return 1
		}
	done
}

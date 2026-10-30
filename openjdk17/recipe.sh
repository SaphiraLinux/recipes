#!/bin/sh

pkgname=openjdk17
pkgver=17.0.17_p10
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='OpenJDK 17 development kit, headless (javac, jar, jlink; runtime split out)'
license='GPL-2.0-only WITH Classpath-exception-2.0'
origin=openjdk17
repo=saphira
url=https://openjdk.org/
source=https://github.com/openjdk/jdk17u/archive/jdk-17.0.17+10.tar.gz
sha256=6c8015923a618a3568d8ca92ec8bd263116461b1a7320f9c4176b813e3ea95a6

depends="
    openjdk17-jre-headless
    ca-certificates
"

makedepends="
    alsa-lib-dev
    autoconf
    binutils
    bash
    clang
    cups-dev
    file
    fontconfig-dev
    freetype
    gcc
    giflib-dev
    lcms2-dev
    libjpeg-turbo-dev
    libpng
    libX11-dev
    libXrender-dev
    make
    openjdk17-bootstrap
    pkgconf
    saphira-linux-uapi-headers
    unzip
    util-linux-dev
    xorgproto
    zip
    zlib-dev
"

subpackages="openjdk17-jre-headless openjdk17-doc"

# Headless Saphira JDK: no X, no ALSA, no CUPS (headless-server
# distribution policy, normative). --enable-headless-only drops the
# GUI stacks; freetype+fontconfig stay (headless rasterising is
# legitimate). Split agreed 2026-10-28: openjdk17 is the full kit and
# depends on openjdk17-jre-headless (runtime only: java, keytool,
# conf/, lib/); servers install just the JRE. Demos are not built
# (examples, not capability); lib/src.zip is dropped (sources remain
# in the vendored tarball and upstream tag; keeps installs lean).
recipe_build()
{
	mkdir -p "$BUILDDIR" && cd "$BUILDDIR"
	# Saphira baseline is x86-64-v3, carried by gcc itself
	# (--with-arch); clang does not inherit it, so pass it
	# explicitly, per-arch like the gcc recipe.
	case "${SAPHIRA_ARCH:-x86_64}" in
	x86_64) MARCH_FLAG="-march=x86-64-v3" ;;
	aarch64) MARCH_FLAG="-march=armv8-a" ;;
	riscv64) MARCH_FLAG="-march=rv64gc" ;;
	*) echo "ERROR: unsupported SAPHIRA_ARCH for openjdk17" >&2; return 1 ;;
	esac
	# Via bash: GitHub codeload tarballs do not preserve configure's
	# exec bit (verified: permission denied on direct exec).
	# CC is clang, so --with-toolchain-type=clang is passed below:
	# configure defaults to the gcc toolchain and rejects a clang
	# CC otherwise (proven 06:31Z).
	CC=clang CXX=clang++ bash "$SRC/configure" \
		--prefix=/usr/lib/jvm/java-17-openjdk \
		--with-boot-jdk=/usr/lib/jvm/java-17-bootstrap \
		--with-jobs=${JOBS:-$(nproc)} \
		--enable-headless-only \
		--with-toolchain-type=clang \
		--with-zlib=system \
		--with-libpng=system \
		--with-libjpeg=system \
		--with-giflib=system \
		--with-lcms=system \
		--with-freetype=system \
		--with-debug-level=release \
		--with-native-debug-symbols=none \
		--with-jvm-variants=server \
		--with-jtreg=no \
		--enable-dtrace=no \
		--disable-warnings-as-errors \
		--disable-precompiled-headers \
		--with-version-pre= \
		--with-version-build=10 \
		--with-version-opt=saphira-r1 \
		--with-vendor-name=Saphira \
		--with-vendor-url=https://saphira.vm2.uk/ \
		--with-extra-cflags="$MARCH_FLAG ${CFLAGS-}" \
		--with-extra-cxxflags="$MARCH_FLAG ${CXXFLAGS-}" \
		--with-extra-ldflags="${LDFLAGS-}" \
		|| {
			echo "configure failed; compiler-check section of config.log:" >&2
			n=$(grep -n 'checking whether the C compiler works' config.log 2>/dev/null | tail -1 | cut -d: -f1 || true)
			[ -n "$n" ] || n=1
			tail -n +"$n" config.log >&2 || true
			return 1
		}
	make images
	# Verification gate: the just-built runtime must identify itself
	# and run code, or nothing ships.
	"$BUILDDIR"/images/jdk/bin/java -version || return 1
	mkdir -p "$BUILDDIR/smoke" && cd "$BUILDDIR/smoke"
	printf '%s\n' 'public class Hello {' \
		'    public static void main(String[] a) {' \
		'        System.out.println("saphira-jdk-smoke-ok");' \
		'    }' '}' > Hello.java
	"$BUILDDIR"/images/jdk/bin/javac Hello.java || return 1
	[ "$("$BUILDDIR"/images/jdk/bin/java Hello)" = "saphira-jdk-smoke-ok" ] || return 1
}

recipe_install()
{
	mkdir -p "$PKGDEST/usr/lib/jvm/java-17-openjdk"
	cp -a "$BUILDDIR"/images/jdk/. \
		"$PKGDEST/usr/lib/jvm/java-17-openjdk/"
	rm -f "$PKGDEST/usr/lib/jvm/java-17-openjdk/lib/src.zip"
	# /usr/bin entry points: created for every tool here, split-owned
	# by payload (java+keytool travel with the JRE split).
	mkdir -p "$PKGDEST/usr/bin"
	for f in "$PKGDEST/usr/lib/jvm/java-17-openjdk/bin/"*; do
		ln -s "../lib/jvm/java-17-openjdk/bin/${f##*/}" \
			"$PKGDEST/usr/bin/${f##*/}"
	done
	install -D -m 0644 "$SRC/LICENSE" \
		"$PKGDEST/usr/share/licenses/openjdk17/LICENSE"
	install -d -m 0755 "$PKGDEST/usr/share/saphira/hooks.d/$pkgname"
	install -m 0755 "$RECIPE_DIR/files/hooks-cacerts" \
		"$PKGDEST/usr/share/saphira/hooks.d/$pkgname/post-install"
	install -m 0755 "$RECIPE_DIR/files/hooks-cacerts" \
		"$PKGDEST/usr/share/saphira/hooks.d/$pkgname/post-upgrade"
}

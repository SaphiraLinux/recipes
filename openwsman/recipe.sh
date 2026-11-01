#!/bin/sh

# openwsman: WS-Management client library (libvirt Hyper-V driver).
# Client library only: no CIM server, no bindings, no plugins.

pkgname=openwsman
pkgver=2.8.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="WS-Management client library"
license="BSD-3-Clause"
origin=openwsman
repo=saphira
url=https://github.com/Openwsman/openwsman
source=https://github.com/Openwsman/openwsman/archive/refs/tags/v${pkgver}.tar.gz
sha256=22f7dd418eda4d6e4d1c497fcc2a3e2ee91eeff3c19f4a4447dfaec38fd2b87b

# Client-only selection: server, CIM plugin, examples, all language
# bindings, swig plugin and tests stay off (each is a separate scope;
# none is needed for the Hyper-V client). IPv6 + eventing stay on.
makedepends="
    binutils
    cmake
    curl-dev
    gcc
    libxml2-dev
    make
    ninja
    openssl-dev
    pkgconf
"

subpackages="$pkgname-dev"

recipe_build()
{
	# musl port: PTHREAD_MUTEX_RECURSIVE_NP is a glibc extension
	# (verified applicable by real application in scratch).
	patch -d "$SRC" -Np1 -i "$RECIPE_DIR/files/musl-pthread-np.patch" || return 1
	# -DLIB: upstream ignores LIBDIR (own LIB_SUFFIX logic);
	# this is the switch it honors (libftdi1 precedent).
	cmake -S "$SRC" -B "$BUILDDIR" \
		-DCMAKE_C_COMPILER=gcc -DCMAKE_BUILD_TYPE=Release \
		-DBUILD_SHARED_LIBS=ON \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_INSTALL_LIBDIR=lib \
		-DLIB=lib \
		-DDISABLE_SERVER=YES \
		-DBUILD_LIBCIM=NO \
		-DBUILD_EXAMPLES=NO \
		-DBUILD_BINDINGS=NO \
		-DBUILD_PYTHON3=NO \
		-DBUILD_RUBY=NO \
		-DBUILD_PERL=NO \
		-DBUILD_JAVA=NO \
		-DBUILD_CSHARP=NO \
		-DBUILD_SWIG_PLUGIN=NO \
		-DBUILD_TESTS=NO \
		-DENABLE_EVENTING_SUPPORT=YES \
		-DENABLE_IPV6=YES
	cmake --build "$BUILDDIR" -j${JOBS:-$(nproc)}
}

recipe_install()
{
	DESTDIR="$PKGDEST" cmake --install "$BUILDDIR"
	install -D -m 0644 "$SRC/COPYING" \
		"$PKGDEST/usr/share/licenses/openwsman/COPYING"
	# .a/.pc/headers to -dev via the fixed split predicates; the
	# versioned client .so stays in main.
	for p in usr/lib/libwsman.so usr/include/openwsman; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: openwsman payload is missing $p" >&2
			return 1
		}
	done
}

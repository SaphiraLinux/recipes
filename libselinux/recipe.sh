#!/bin/sh

pkgname=libselinux
pkgver=3.11
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="SELinux runtime library (LXC SELinux backend)"
license="Public-Domain"
origin=libselinux
repo=saphira
url=https://github.com/SELinuxProject/selinux
source=https://github.com/SELinuxProject/selinux/releases/download/${pkgver}/libselinux-${pkgver}.tar.gz
sha256=73d419c6e20e874adaa4019372cbd097eecf4d276e13f27ec5e67d35c0bd203c

# libsepol-dev carries the sepol headers this links against; pcre2-dev
# carries the regex engine (USE_PCRE2 defaults to y upstream).
# musl has no fts(3): musl-fts-dev supplies the header (elfutils
# precedent) and -lfts links selinux_restorecon.o (FTS_LDLIBS is
# honored by upstream's link line but never assigned -- glibc
# carries fts in libc). The full DT_NEEDED closure needs runtime
# edges (RUNTIME stage proved each): libpcre2-8.so.0, libsepol.so.2
# (sefcontext_compile links it shared) and libgcc_s.so.1
# (-fexceptions in upstream CFLAGS; ace/gcc-libs precedent).
depends="
    gcc-libs
    libsepol
    musl-fts
    pcre2
"

# No binding stack: the Ruby/Python wrappers are separate opt-in make
# targets (pywrap/rubywrap) that plain build/install never invokes, so
# there is nothing to disable (feature policy: no binding stack without
# a consumer).
makedepends="
    binutils
    gcc
    libsepol-dev
    make
    musl-fts-dev
    pcre2-dev
    pkgconf
"

subpackages="$pkgname-dev $pkgname-doc"

recipe_build()
{
	# Upstream honors PREFIX/DESTDIR/LIBDIR/INCLUDEDIR/SHLIBDIR.
	# Runtime objects stay in /usr/lib: every consumer (liblxc
	# tools) lives under /usr, so /lib is not warranted.
	# No unit-test target ships upstream (test: is empty); the
	# link-level proof is the LXC build consuming this library,
	# plus a getenforce smoke test after installation.
	make -j${JOBS:-$(nproc)} \
		PREFIX=/usr \
		LIBDIR=/usr/lib \
		SHLIBDIR=/usr/lib \
		INCLUDEDIR=/usr/include \
		FTS_LDLIBS=-lfts
}

recipe_install()
{
	make DESTDIR="$PKGDEST" \
		PREFIX=/usr \
		LIBDIR=/usr/lib \
		SHLIBDIR=/usr/lib \
		INCLUDEDIR=/usr/include \
		FTS_LDLIBS=-lfts \
		install
	install -D -m 0644 "$SRC/LICENSE" \
		"$PKGDEST/usr/share/licenses/libselinux/LICENSE"
	# The static archive and .pc file travel to -dev and the man
	# pages to -doc via the fixed buildpkg-single predicates; the
	# versioned .so stays in main.
	for p in usr/lib/libselinux.so usr/include/selinux usr/share/man; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: libselinux payload is missing $p" >&2
			return 1
		}
	done
}

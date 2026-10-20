#!/bin/sh

# cyrus-sasl: SASL authentication library (libvirt -Dsasl).
# saslauthd ships with dual-init units (policy for daemon packages),
# never enabled at install.

pkgname=cyrus-sasl
pkgver=2.1.28
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="SASL authentication library and saslauthd"
license="BSD-4-Clause"
origin=cyrus-sasl
repo=saphira
url=https://github.com/cyrusimap/cyrus-sasl
source=https://github.com/cyrusimap/cyrus-sasl/releases/download/cyrus-sasl-${pkgver}/cyrus-sasl-${pkgver}.tar.gz
sha256=7ccfc6abd01ed67c1a0924b353e526f1b766b21f42d4562ee635a8ebfc5bb38c

# --disable-gssapi: no Kerberos in-tree (GSSAPI mechanism gap is
# documented, not silent; PLAIN/LOGIN-via-flags below plus
# DIGEST-MD5/SCRAM/OTP/ANON ship). --with-dblib=gdbm: sasldb
# without Berkeley DB (absent). NTLM/LOGIN stay off: upstream marks
# them unsupported, which is upstream's call, not a Saphira cut.
# saslauthd has no disable knob; it ships with both unit formats.
# gcc16 strictness: PROTOTYPES via CPPFLAGS (md5global.h documents it
# as settable "with C compiler flags"; without it PROTO_LIST expands
# empty and lib/md5.c fails arity checks) + time-t/md5-cast fixes
# adapted from Alpine (upstream PR #873 did not apply to the 2.1.28
# tarball, so the call sites are fixed here against actual context;
# the configure.ac hunk is superseded by the CPPFLAGS mechanism, which
# avoids autoreconf drift).
makedepends="
    binutils
    gcc
    gdbm-dev
    linux-pam-dev
    make
    openssl-dev
    pkgconf
"

subpackages="$pkgname-dev $pkgname-doc"

recipe_build()
{
	patch -Np1 -i "$RECIPE_DIR/files/time-h-gcc14.patch" || return 1
	patch -Np1 -i "$RECIPE_DIR/files/gcc16-md5-casts.patch" || return 1
	CPPFLAGS="${CPPFLAGS-} -DPROTOTYPES=1" ./configure \
		--prefix=/usr \
		--sysconfdir=/etc \
		--localstatedir=/var \
		--libdir=/usr/lib \
		--disable-gssapi \
		--with-dblib=gdbm \
		--with-openssl \
		--with-plugindir=/usr/lib/sasl2
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
	install -D -m 0644 "$SRC/COPYING" \
		"$PKGDEST/usr/share/licenses/cyrus-sasl/COPYING"
	install -D -m 0755 "$RECIPE_DIR/files/saslauthd.initd" \
		"$PKGDEST/etc/init.d/saslauthd"
	install -D -m 0644 "$RECIPE_DIR/files/saslauthd.service" \
		"$PKGDEST/usr/lib/systemd/system/saslauthd.service"
	# .a/.pc/headers to -dev via the fixed split predicates; the
	# versioned .so, plugins and saslauthd stay in main.
	for p in usr/lib/libsasl2.so usr/include/sasl \
		etc/init.d/saslauthd \
		usr/lib/systemd/system/saslauthd.service; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: cyrus-sasl payload is missing $p" >&2
			return 1
		}
	done
}

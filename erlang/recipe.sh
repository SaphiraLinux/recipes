#!/bin/sh

pkgname=erlang
pkgver=27.3.4.19
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Erlang/OTP runtime and toolchain (RabbitMQ message bus)"
license='Apache-2.0'
origin=erlang
repo=saphira
url=https://www.erlang.org/
source=https://github.com/erlang/otp/releases/download/OTP-27.3.4.19/otp_src_27.3.4.19.tar.gz
sha256=866307e64e245e86bee15b3807030a998e59873d7480d6fae1e40b432a3d12b7

depends="
    gcc-libs
    openssl
    ncurses
    zlib
"

makedepends="
    binutils
    gcc
    make
    perl
    flex
    pkgconf
    openssl-dev
    ncurses-dev
    zlib-dev
"

# Headless by policy, docs off the critical path:
# - wx (GUI toolkit) is forbidden in the headless universe and
#   would need a display stack; --without-wx is deliberate.
# - Java (jinterface) has no JDK in the universe; skipped.
# - ODBC has no unixODBC in the universe; skipped.
# - HTML/PDF docs need fop/xsltproc toolchains; `make` does not
#   build them (only `make docs` does), so nothing extra is cut.
recipe_build()
{
	# OTP's build system is inherently in-source: the top-level
	# wrapper cds into each application directory under ERL_TOP and
	# the make sub-configure writes $ERL_TOP/Makefile, so a
	# BUILDDIR configure leaves the build dir empty ("No targets
	# specified and no makefile found"). Build on a copy, keeping
	# the vendored extraction pristine.
	cp -r "$SRC/." "$BUILDDIR/" && cd "$BUILDDIR"
	./configure --prefix=/usr --sysconfdir=/etc \
		--localstatedir=/var \
		--without-javac --without-wx --without-odbc
	make
}

recipe_install()
{
	make -C "$BUILDDIR" DESTDIR="$PKGDEST" install
	for p in \
		usr/bin/erl \
		usr/bin/erlc \
		usr/bin/epmd \
	; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: erlang payload is missing $p" >&2
			return 1
		}
	done
}

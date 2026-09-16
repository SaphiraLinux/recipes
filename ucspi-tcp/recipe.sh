#!/bin/sh

pkgname=ucspi-tcp
pkgver=0.88
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="DJB TCP socket tools: tcpserver/tcpclient/tcprules (qmail-smtpd frontend)"
# D.J. Bernstein placed ucspi-tcp 0.88 in the public domain.
license="public-domain"
origin=ucspi-tcp
repo=main
url=http://cr.yp.to/ucspi-tcp.html
source=http://cr.yp.to/ucspi-tcp/ucspi-tcp-0.88.tar.gz
sha256=4a0615cab74886f5b4f7e8fd32933a07b955536a3476d74ea087a3ea66a23e9c

depends=""

makedepends="
    binutils
    gawk
    gcc
    make
"

recipe_build()
{
	# Port patch (see files/saphira-port.patch, proven by a scratch
	# build plus tcpserver/tcpclient echo test): missing system
	# headers everywhere (unistd/errno/socket/stat), K&R mains
	# (including every try* config probe, which otherwise
	# misdetects), DJB readwrite.h delegating to unistd.h, errno
	# decl dropped from error.h, socket.h prototypes, hier.c
	# install-function prototypes, and DESTDIR support in
	# install.c (ownership is -1/-1 no-ops, kept as-is).
	patch -p1 < "$RECIPE_DIR/files/saphira-port.patch"
	# Saphira home is /usr (upstream default /usr/local); the rule
	# only reads the first line.
	printf '%s\n' '/usr' > conf-home
	# -Wno-error=incompatible-pointer-types follows the nginx
	# precedent: buffer_init's K&R op type vs correct ssize_t
	# read/write decls is benign (actual calls match), while the
	# correct decls fix real 64-bit truncation bugs.
	printf '%s\n' 'gcc -O2 -pipe -g -std=gnu17 -Wno-error=incompatible-pointer-types' > conf-cc
	printf '%s\n' 'gcc -g' > conf-ld
	make -j${JOBS:-$(nproc)} it
}

recipe_install()
{
	cd "$SRC"
	# install(1)-style single mkdir needs the DESTDIR parent to
	# exist (true on real roots, not in staging).
	mkdir -p "$PKGDEST/usr"
	DESTDIR="$PKGDEST" ./install
	# No service units in r1: tcpserver is the transport; the
	# qmail-smtpd listener definitions (ports, rules, certs) ship
	# with the SMTP-listener phase, not the tool package. No
	# identities either: tcpserver drops to the invoking service's
	# user via -u/-g.
}

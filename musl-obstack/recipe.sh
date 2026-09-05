#!/bin/sh

pkgname=musl-obstack
pkgver=1.2.3
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Obstack functions from glibc for musl libc"
license="GPL-2.0-or-later MIT"
origin=musl-obstack
repo=main
url=https://github.com/void-linux/musl-obstack
source=https://github.com/void-linux/musl-obstack/archive/refs/tags/v1.2.3.tar.gz
sha256=9ffb3479b15df0170eba4480e51723c3961dbe0b461ec289744622db03a69395

depends=""
makedepends="
    gcc
"

subpackages="
    $pkgname-dev
"

recipe_build()
{
	# Two translation units; same direct-compile approach as musl-fts.
	# HAVE_LIBINTL_H stays undefined: no i18n catalog support here.
	: > config.h
	for src in obstack.c obstack_printf.c; do
		gcc -I. ${CFLAGS--O2} -c "$SRC/$src" -o "${src%.c}.o"
		gcc -I. ${CFLAGS--O2} -fPIC -c "$SRC/$src" -o "${src%.c}.pic.o"
	done
	ar crD libobstack.a obstack.o obstack_printf.o
	ranlib libobstack.a
	gcc -shared -Wl,-soname,libobstack.so.1 \
		-o libobstack.so.1.0.0 obstack.pic.o obstack_printf.pic.o
	ln -sf libobstack.so.1.0.0 libobstack.so.1
	ln -sf libobstack.so.1 libobstack.so
}

recipe_install()
{
	install -D -m 0644 libobstack.a "$PKGDEST/usr/lib/libobstack.a"
	for so in libobstack.so.1.0.0 libobstack.so.1; do
		install -m 0755 "$so" "$PKGDEST/usr/lib/$so"
	done
	ln -sf libobstack.so.1.0.0 "$PKGDEST/usr/lib/libobstack.so"
	install -d -m 0755 "$PKGDEST/usr/include"
	install -m 0644 "$SRC/obstack.h" "$PKGDEST/usr/include/obstack.h"
}

#!/bin/sh

pkgname=lua54
pkgver=5.4.8
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Lua 5.4 scripting language (shared library, interpreter, compiler)"
license="MIT"
origin=lua54
repo=main
url=https://www.lua.org/
source=https://www.lua.org/ftp/lua-5.4.8.tar.gz
sha256=4f18ddae154e793e46eeab727c59ef1c0c0c2b744e7b94219710d76f530629ae

depends=""

makedepends="
    gcc
    make
"

subpackages="
    $pkgname-dev
"

recipe_build()
{
	# Proven v0 decision kept: readline stays out to avoid an ncurses
	# toolchain dependency in the interpreter.  The 5.4 makefile builds
	# no shared library itself, so the PIC objects are linked into
	# liblua.so afterwards for consumers like rspamd.
	make all \
		MYCFLAGS="${CFLAGS-} -fPIC" \
		MYLDFLAGS="${LDFLAGS-}" \
		SYSLIBS="-lm -ldl"
	gcc -shared -Wl,-soname,liblua.so.${pkgver%.*} \
		-o src/liblua.so.${pkgver%.*} $(ls src/*.o | grep -v 'lua\.o\|luac\.o') \
		-lm -ldl
	cd src && ln -sf "liblua.so.${pkgver%.*}" liblua.so && cd ..
}

recipe_install()
{
	install -d -m 0755 "$PKGDEST/usr/bin" "$PKGDEST/usr/lib" \
		"$PKGDEST/usr/include" "$PKGDEST/usr/lib/pkgconfig"
	install -m 0755 src/lua "$PKGDEST/usr/bin/lua"
	install -m 0755 src/luac "$PKGDEST/usr/bin/luac"
	install -m 0644 src/liblua.a "$PKGDEST/usr/lib/"
	for so in liblua.so.${pkgver%.*} liblua.so; do
		install -m 0755 "src/$so" "$PKGDEST/usr/lib/$so"
	done
	install -m 0644 src/lua.h src/luaconf.h src/lualib.h src/lauxlib.h src/lua.hpp "$PKGDEST/usr/include/"
	cat > "$PKGDEST/usr/lib/pkgconfig/lua.pc" <<EOF
prefix=/usr
libdir=/usr/lib
includedir=/usr/include

Name: Lua
Description: Lua 5.4 scripting language
Version: ${pkgver}
Libs: -L\${libdir} -llua
Cflags: -I\${includedir}
EOF
	cp "$PKGDEST/usr/lib/pkgconfig/lua.pc" \
		"$PKGDEST/usr/lib/pkgconfig/lua54.pc"
	cp "$PKGDEST/usr/lib/pkgconfig/lua.pc" \
		"$PKGDEST/usr/lib/pkgconfig/lua-5.4.pc"
}

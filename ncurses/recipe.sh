#!/bin/sh
pkgname=ncurses
pkgver=6.5
pkgrel=10
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Terminal text UI library with wide-character support'
license='MIT'
origin=ncurses
repo=saphira
url=https://invisible-island.net/ncurses/
ncurses_sha256=136d91bc269a9a5785e5f9e980bc76ab57428f604ce3e5a5a90cebc767971cc6
depends=""
makedepends="gawk gcc make"
subpackages="$pkgname-dev $pkgname-doc"
recipe_build() {
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/ncurses-6.5.tar.gz"
	cd "$SRC"
	echo "$ncurses_sha256  $RECIPE_DIR/files/ncurses-6.5.tar.gz" | sha256sum -c -
	AWK=/usr/bin/mawk ./configure --prefix=/usr \
		--libdir=/usr/lib \
		--with-shared \
		--without-termlib \
		--with-terminfo-dirs=/usr/share/terminfo \
		--enable-widec \
		--without-ada \
		--without-tests \
		--without-cxx-binding \
		--disable-stripping
	make -j${JOBS:-$(nproc)}
}
recipe_install() {
	make -C "$SRC" DESTDIR="$PKGDEST" install
	# Compatibility symlinks: many packages (readline, gdb, ...) probe
	# -lcurses / -lncurses. With --without-termlib everything lives in
	# libncursesw, so point the non-wide names at the wide library.
	# FHS non-usrmerged: /bin|/sbin consumers (bash needs
	# libncursesw.so.6) take the runtime SONAME chain from /lib; dev
	# linker names stay in /usr/lib pointing back (acl precedent).
	mkdir -p "$PKGDEST/lib"
	for lib in "$PKGDEST/usr/lib/libncursesw.so.6"*; do
		[ -e "$lib" ] && mv "$lib" "$PKGDEST/lib/"
	done
	for compat in libncurses.so.6 libcurses.so.6; do
		ln -sf libncursesw.so.6 "$PKGDEST/lib/$compat"
	done
	for dev in libncursesw.so libncurses.so libcurses.so libtermcap.so; do
		link="$PKGDEST/usr/lib/$dev"
		[ -L "$link" ] || continue
		target=$(readlink "$link")
		case $target in */*) continue;; esac
		[ -e "$PKGDEST/lib/$target" ] && ln -sf "../../lib/$target" "$link"
	done
	ln -sf libncursesw.so "$PKGDEST/usr/lib/libncurses.so"
	# termcap ABI compat: legacy consumers (inetutils telnet/telnetd,
	# ...) probe -ltermcap.  The termcap emulation entry points live in
	# libncursesw; the symlink only provides the link-time name, and the
	# resulting binaries keep their DT_NEEDED on libncursesw.so.6 via
	# its SONAME.  termcap.h ships in the -dev header set.
	ln -sf libncursesw.so "$PKGDEST/usr/lib/libtermcap.so"
	# pkg-config files: consumers (procps-ng, mc, ...) probe ncursesw
	mkdir -p "$PKGDEST/usr/lib/pkgconfig"
	cat > "$PKGDEST/usr/lib/pkgconfig/ncursesw.pc" <<'PCEOF'
prefix=/usr
exec_prefix=${prefix}
libdir=${prefix}/lib
includedir=${prefix}/include
major_version=6
version=6.5.20240629
Name: ncursesw
Description: ncurses wide-character library
Version: ${version}
Requires:
Libs: -L${libdir} -lncursesw
Cflags: -I${includedir}
PCEOF
	cat > "$PKGDEST/usr/lib/pkgconfig/ncurses.pc" <<'PCEOF'
prefix=/usr
exec_prefix=${prefix}
libdir=${prefix}/lib
includedir=${prefix}/include
major_version=6
version=6.5.20240629
Name: ncurses
Description: ncurses library (non-wide compat name)
Version: ${version}
Requires:
Libs: -L${libdir} -lncursesw
Cflags: -I${includedir}
PCEOF
	ln -sf libncursesw.so "$PKGDEST/usr/lib/libcurses.so"
}

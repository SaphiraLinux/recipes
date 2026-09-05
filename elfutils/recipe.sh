pkgname=elfutils
pkgver=0.193
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='ELF/DWARF object file access libraries (libelf, libdw) - libs only, v0 scope'
license='GPL-3.0-or-later OR LGPL-3.0-or-later'
origin=elfutils
repo=main
url=https://sourceware.org/elfutils/
# Vendored: https://sourceware.org/elfutils/ftp/0.193/elfutils-0.193.tar.bz2
elfutils_sha256=7857f44b624f4d8d421df851aaae7b1402cfe6bcdd2d8049f15fc07d3dde7635

subpackages="elfutils-dev"

makedepends="
	argp-standalone
	bzip2
	binutils
	bison
	flex
	gawk
	gcc
	saphira-kernel-headers=7.1.5
	m4
	make
	musl-fts-dev
	musl-obstack-dev
	pkgconf
	zlib-dev
"

# v0-proven scope: libraries only (src/ tools need GNU-only bits like
# FNM_EXTMATCH on musl). LIBS carries the musl compat libs.
recipe_build()
{
	EUBALL="$RECIPE_DIR/files/elfutils-0.193.tar.bz2"
	echo "$elfutils_sha256  $EUBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$EUBALL"
	mkdir -p "$SRC/build" && cd "$SRC/build"
	export LIBS="-largp -lfts -lobstack"
	../configure --prefix=/usr \
		--disable-debuginfod \
		--disable-libdebuginfod \
		--disable-debuginfod-ima-verification \
		--disable-demangler \
		--disable-nls \
		--without-bzlib \
		--without-lzma \
		--without-zstd \
		--disable-dependency-tracking
	for d in lib libelf libebl libcpu backends libdwelf libdwfl_stacktrace libdwfl libdw; do
		make -j${JOBS:-$(nproc)} -C "$d"
	done
}

recipe_install()
{
	for d in lib libelf libebl libcpu backends libdwelf libdwfl_stacktrace libdwfl libdw; do
		make -C "$SRC/build/$d" DESTDIR="$PKGDEST" install
	done
	install -d "$PKGDEST/usr/lib/pkgconfig" "$PKGDEST/usr/include/elfutils" "$PKGDEST/usr/share/licenses/elfutils"
	for pc in libelf libdw; do
		[ -f "$SRC/build/config/$pc.pc" ] && install -m 0644 "$SRC/build/config/$pc.pc" "$PKGDEST/usr/lib/pkgconfig/$pc.pc"
	done
	install -m 0644 "$SRC/version.h" "$PKGDEST/usr/include/elfutils/version.h"
	install -m 0644 "$SRC/COPYING" "$PKGDEST/usr/share/licenses/elfutils/COPYING"
}

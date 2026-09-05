pkgname=wireless-tools
pkgver=29
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Wireless Extensions tools (iwconfig, iwlist, ifrename)'
license=GPL-2.0-only
origin=wireless-tools
repo=main
url=https://hewlettpackard.github.io/wireless-tools/
source=https://hewlettpackard.github.io/wireless-tools/wireless_tools.29.tar.gz
sha256=6fb80935fe208538131ce2c4178221bab1078a1656306bce8909c19887e2e5a1

makedepends="
	binutils
	gcc
	saphira-kernel-headers=7.1.5
	make
"

recipe_build()
{
	if [ -f "$RECIPE_DIR/files/fix_iwlist_scanning.patch" ]; then
		patch -Np1 -i "$RECIPE_DIR/files/fix_iwlist_scanning.patch"
	# musl: basename() lives in libgen.h, not string.h
	sed -i "1i #include <libgen.h>" ifrename.c
	fi
	make -j1 CFLAGS="-Os -W -Wall -Wno-implicit-fallthrough -Wno-pointer-sign"
}

recipe_install()
{
	install -d "$PKGDEST/usr/sbin" "$PKGDEST/usr/bin" "$PKGDEST/usr/lib" "$PKGDEST/usr/include" "$PKGDEST/usr/share/man/man8"
	for b in iwconfig iwlist iwpriv iwspy ifrename; do
		install -m 755 "$SRC/$b" "$PKGDEST/usr/sbin/$b"
	done
	install -m 755 "$SRC/iwevent" "$PKGDEST/usr/sbin/iwevent"
	install -m 755 "$SRC/iwgetid" "$PKGDEST/usr/sbin/iwgetid"
	install -m 644 "$SRC/libiw.so.29" "$PKGDEST/usr/lib/libiw.so.29"
	ln -sf libiw.so.29 "$PKGDEST/usr/lib/libiw.so"
	install -m 644 "$SRC/iwlib.h" "$PKGDEST/usr/include/iwlib.h"
	for m in "$SRC"/*.8; do
		install -m 644 "$m" "$PKGDEST/usr/share/man/man8/"
	done
}

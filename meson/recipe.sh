#!/bin/sh
pkgname=meson
pkgver=1.8.2
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Fast and user-friendly build system'
license='Apache-2.0'
origin=meson
repo=saphira
url=https://mesonbuild.com/
meson_sha256=c105816d8158c76b72adcb9ff60297719096da7d07f6b1f000fd8c013cd387af
depends="python3"
makedepends="python3"
recipe_build()
{
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/meson-1.8.2.tar.gz"
	cd "$SRC"
	echo "$meson_sha256  $RECIPE_DIR/files/meson-1.8.2.tar.gz" | sha256sum -c -
}

recipe_install()
{
	install -d "$PKGDEST/usr/lib/python3.14/site-packages" "$PKGDEST/usr/bin"
	cp -a "$SRC/mesonbuild" "$PKGDEST/usr/lib/python3.14/site-packages/"
	cat > "$PKGDEST/usr/bin/meson" <<'EOF'
#!/usr/bin/python3
import sys
from mesonbuild.mesonmain import main
sys.exit(main())
EOF
	chmod 0755 "$PKGDEST/usr/bin/meson"
}

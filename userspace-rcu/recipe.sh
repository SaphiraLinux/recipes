#!/bin/sh

pkgname=userspace-rcu
pkgver=0.15.6
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Userspace RCU (read-copy-update) data-structure library"
license="LGPL-2.1-or-later"
origin=userspace-rcu
repo=main
url=https://liburcu.org/
# Hard glusterfs/xfsprogs configure/build requirement. This recipe is
# canonical for the urcu line: replaces is the apk-tools v3 ownership
# handover from the retired liburcu splits (solver ignores replaces; it
# is conflict metadata only). Main takes the sonames, -dev the headers
# and pkg-config files.
vendor=https://lttng.org/files/urcu/userspace-rcu-0.15.6.tar.bz2
sha256=850b192096eb11ebf2c70e8f97bc7da7479ee41da1bebeb44e3986908bac414f
replaces="liburcu liburcu-dev liburcu-doc"

depends=""

subpackages="$pkgname-dev"

makedepends="
    gcc
    make
"

recipe_build()
{
	# Local archive wins when present (verified, never re-downloaded);
	# otherwise build from the builder-verified $SOURCE_ARCHIVE (see
	# the gpsd recipe comment for why the re-extract is harmless).
	URCUBALL="$RECIPE_DIR/files/userspace-rcu-0.15.6.tar.bz2"
	if [ -f "$URCUBALL" ]; then
		echo "$sha256  $URCUBALL" | sha256sum -c -
	else
		[ -n "${SOURCE_ARCHIVE-}" ] && [ -f "$SOURCE_ARCHIVE" ] \
			|| { echo "ERROR: no local userspace-rcu-0.15.6.tar.bz2 and no fetched SOURCE_ARCHIVE" >&2; return 1; }
		URCUBALL=$SOURCE_ARCHIVE
	fi
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$URCUBALL"
	cd "$SRC"
	./configure --prefix=/usr --sysconfdir=/etc --disable-static
	make -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make DESTDIR="$PKGDEST" install
}

#!/bin/sh

# sanlock: shared-storage lease manager (libvirt -Dsanlock).
# libsanlock_client is the client library; sanlockd + wdmd are the
# daemons (watchdog-armed fencing -- see below). Both daemons ship
# dual-init units, never enabled at install.

pkgname=sanlock
pkgver=5.1.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="Shared-storage lease manager (libsanlock, sanlockd, wdmd)"
license="GPL-2.0-or-later AND LGPL-2.0-or-later"
origin=sanlock
repo=saphira
url=https://github.com/sanlock/sanlock
# Codeberg is upstream's post-pagure home (pagure sunset 2026).
source=https://codeberg.org/sanlock/sanlock/archive/sanlock-${pkgver}.tar.gz
sha256=dcd814b43677475a6eb1c96aef89b2b5b87ec100b4412c728fa28153b15a09bc

# Handwritten makefiles honour BINDIR/LIBDIR/HEADIR/VARDIR. LIBDIR
# defaults to lib64 (forbidden) -- overridden. Daemon link needs
# uuid (util-linux-dev), aio (libaio-dev), blkid (util-linux-dev)
# and devmapper headers (lvm2-dev; the headers moved out of lvm2
# main with its three-way split, so the bare lvm2 makedepend that
# used to provide them now resolves to lvm2-dev).
makedepends="
    binutils
    gcc
    libaio-dev
    lvm2-dev
    make
    util-linux-dev
"

subpackages="$pkgname-dev $pkgname-doc"

recipe_build()
{
	# musl/gcc strictness fixes (Alpine aports main/sanlock, same 5.1.1,
	# verified applicable by real application in scratch): missing
	# string.h/stdint.h includes (C23 implicit declarations are errors),
	# basename needs libgen.h.
	patch -Np1 -i "$RECIPE_DIR/files/c23.patch" || return 1
	patch -Np1 -i "$RECIPE_DIR/files/basename-include.patch" || return 1
	make -j${JOBS:-$(nproc)} \
		BINDIR=/usr/sbin \
		LIBDIR=/usr/lib \
		HEADIR=/usr/include \
		VARDIR=/var
}

recipe_install()
{
	make DESTDIR="$PKGDEST" \
		BINDIR=/usr/sbin \
		LIBDIR=/usr/lib \
		HEADIR=/usr/include \
		VARDIR=/var \
		install
	install -D -m 0755 "$RECIPE_DIR/files/sanlock.initd" \
		"$PKGDEST/etc/init.d/sanlock"
	install -D -m 0644 "$RECIPE_DIR/files/sanlock.service" \
		"$PKGDEST/usr/lib/systemd/system/sanlock.service"
	install -D -m 0755 "$RECIPE_DIR/files/wdmd.initd" \
		"$PKGDEST/etc/init.d/wdmd"
	install -D -m 0644 "$RECIPE_DIR/files/wdmd.service" \
		"$PKGDEST/usr/lib/systemd/system/wdmd.service"
	# .a/.pc/headers to -dev via the fixed split predicates; the
	# shared libs, daemons and tools stay in main.
	for p in usr/lib/libsanlock_client.so usr/include/sanlock.h \
		usr/sbin/sanlock usr/sbin/wdmd \
		etc/init.d/sanlock etc/init.d/wdmd \
		usr/lib/systemd/system/sanlock.service \
		usr/lib/systemd/system/wdmd.service; do
		[ -e "$PKGDEST/$p" ] || {
			echo "ERROR: sanlock payload is missing $p" >&2
			return 1
		}
	done
}

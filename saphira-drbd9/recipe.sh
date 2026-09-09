#!/bin/sh

pkgname=saphira-drbd9
pkgver=9.3.3
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='DRBD 9.3.3 out-of-tree kernel modules for kernel 7.2.2 (Saphira-signed)'
license=GPL-2.0-or-later
origin=saphira-drbd9
repo=saphira
url=https://linbit.com/drbd/
# Multi-node DRBD (quorum, tiebreaker, 3+ nodes): the in-tree 8.4 driver
# cannot do this, hence the out-of-tree 9.x module, following the
# saphira-zfs operator-staged pattern. Managed at runtime by drbd-utils
# (separate recipe, covers 8.4/9.x drivers).
vendor=https://pkg.linbit.com/downloads/drbd/9/drbd-9.3.3.tar.gz
sha256=a7bfb016070c31df1c738569ca8cc5e5fc337dd449147f7bf62e746d87d38f21

depends=""

makedepends="
    bash
    binutils
    diffutils
    gawk
    gcc
    make
    patch
    perl
    saphira-kernel-headers=7.2.2
"

# Build inputs supplied via the /input staging directory (operator-only
# build - the queue daemon cannot supply /input, same as saphira-zfs):
#   buildpkg saphira-drbd9 /build/drbd9-input
#   /build/drbd9-input/linux-7.2.2/   pruned built kernel tree (kmod-ready)
#   /build/drbd9-input/saphira-module.pem   module signing key (never in /recipes)
KDIR_NAME=linux-7.2.2
KVER=7.2.2

recipe_build()
{
	KDIR="$SRC/$KDIR_NAME"
	KEY="$SRC/saphira-module.pem"
	[ -f "$KDIR/Makefile" ] || { echo "ERROR: kernel build tree missing at $KDIR (staged /input?)" >&2; return 1; }
	[ -f "$KEY" ] || { echo "ERROR: module signing key missing at $KEY (staged /input?)" >&2; return 1; }
	[ -x "$KDIR/scripts/sign-file" ] || { echo "ERROR: $KDIR/scripts/sign-file not built" >&2; return 1; }

	SRCBALL="$RECIPE_DIR/files/drbd-9.3.3.tar.gz"
	if [ -f "$SRCBALL" ]; then
		echo "$sha256  $SRCBALL" | sha256sum -c -
	else
		[ -n "${SOURCE_ARCHIVE-}" ] && [ -f "$SOURCE_ARCHIVE" ] \
			|| { echo "ERROR: no local drbd tarball and no fetched SOURCE_ARCHIVE" >&2; return 1; }
		SRCBALL=$SOURCE_ARCHIVE
	fi
	mkdir -p "$SRC/drbd"
	tar --no-same-owner -C "$SRC/drbd" --strip-components=1 -xf "$SRCBALL"
	cd "$SRC/drbd"

	# SPAAS (spatch-as-a-service) stays at its default: the sandbox has
	# network, and without it the build degrades to local spatch (not
	# packaged) or an empty compat patch and fails visibly at compile
	# time if the kernel actually needs patching - never silently wrong.
	make KDIR="$KDIR" KVER="$KVER" module -j${JOBS:-$(nproc)}

	for ko in $(find . -name '*.ko' -not -name '.*'); do
		"$KDIR/scripts/sign-file" sha256 "$KEY" "$KEY" "$ko"
	done
}

recipe_install()
{
	install -d "$PKGDEST/lib/modules/$KVER/extra"
	for ko in $(find "$SRC/drbd" -name '*.ko' -not -name '.*'); do
		install -m 644 "$ko" "$PKGDEST/lib/modules/$KVER/extra/"
	done
}

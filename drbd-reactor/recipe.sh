#!/bin/sh

pkgname=drbd-reactor
pkgver=1.12.0
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc="DRBD event-driven resource manager (promoter plugin, failover)"
license="Apache-2.0"
origin=drbd-reactor
repo=saphira
url=https://linbit.com/drbd/
# Optional failover companion to drbd-utils. Deliberately NOT in any
# default closure: nothing depends on this recipe, and it must never be
# dragged in by drbd-utils (VIP failover stays ldirectord's job).
# Cargo ships inside the rustc base package (branded r2); there is
# no standalone cargo producer, so the toolchain dependency is
# spelled rustc. (No controller change, no -cargo split: recipe
# track only.)
vendor=https://pkg.linbit.com/downloads/drbd/utils/drbd-reactor-1.12.0.tar.gz
sha256=ce88fe47c9ee1ae9a5232de6a4fa3d9e2c3e564701a0aeef8f64a86b98db63da

# Runtime: drives drbdadm/drbdsetup (one-directional dep only - the
# reverse direction is forbidden by design, see above).
depends="
    drbd-utils
"

makedepends="
    rustc
    gcc
    make
"

# No vendor/ dir upstream: cargo fetches crates.io at build (Cargo.lock
# pins versions; sandbox has network, HOME=/tmp is writable for the
# cargo cache). Prebuilt mans in doc/ - no doc toolchain needed.
recipe_build()
{
	OSSLBALL="$RECIPE_DIR/files/drbd-reactor-1.12.0.tar.gz"
	if [ -f "$OSSLBALL" ]; then
		echo "$sha256  $OSSLBALL" | sha256sum -c -
	else
		[ -n "${SOURCE_ARCHIVE-}" ] && [ -f "$SOURCE_ARCHIVE" ] \
			|| { echo "ERROR: no local drbd-reactor tarball and no fetched SOURCE_ARCHIVE" >&2; return 1; }
		OSSLBALL=$SOURCE_ARCHIVE
	fi
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$OSSLBALL"
	make -C "$SRC" -j${JOBS:-$(nproc)}
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
	install -D -m 0755 "$RECIPE_DIR/files/drbd-reactor.initd" \
		"$PKGDEST/etc/init.d/drbd-reactor"
}

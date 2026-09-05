pkgname=netcat-openbsd
pkgver=1.238
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='OpenBSD netcat with Debian feature patches (proxying, UDP scanning, unix sockets)'
license='BSD-3-Clause'
origin=netcat-openbsd
repo=main
url=https://salsa.debian.org/debian/netcat-openbsd
# Vendored salsa snapshot (debian/latest, 1.238-1), bytes pinned. The
# Debian pool 404s historical tarballs and the salsa repo needs the
# patch machinery, so the whole snapshot is vendored (files/repo.tar.gz):
# https://salsa.debian.org/debian/netcat-openbsd/-/archive/debian-latest/netcat-openbsd-debian-latest.tar.gz
nc_sha256=d1d2c551c33e92ac8ac7da97fcd62285de59f22c98a72c991b7531110126c589

depends="libbsd libmd"
makedepends="gcc make pkgconf libbsd-dev libmd-dev"

recipe_build() {
	tar --no-same-owner -C "$SRC" -xf "$RECIPE_DIR/files/repo.tar.gz"
	echo "$nc_sha256  $RECIPE_DIR/files/repo.tar.gz" | sha256sum -c -
	cd "$SRC/netcat-openbsd-debian-latest"
	# Apply the Debian patch series (Linux port, no-TLS build, timeouts,
	# proxying, unix sockets, ...).
	while read -r patch_name; do
		[ -n "$patch_name" ] || continue
		patch -N -s -p1 -i "debian/patches/$patch_name" < /dev/null \
			|| { echo "ERROR: patch failed: $patch_name" >&2; return 1; }
	done < debian/patches/series
	# Saphira: musl netinet/ip.h lacks IPTOS_DSCP_VA (glibc-only name).
	patch -N -s -p1 -i "$RECIPE_DIR/files/musl-iptos-va.patch" < /dev/null
	# Saphira: musl has no libresolv - bundle the base64 codec and
	# drop the -lresolv link.
	patch -N -s -p1 -i "$RECIPE_DIR/files/musl-b64-resolv.patch" < /dev/null
	# build-without-TLS-support.patch rewrites the Makefile for a
	# plain libbsd build.
	make CC=cc PKG_CONFIG=pkg-config \
		CFLAGS="${CFLAGS--O2}" \
		LDFLAGS="${LDFLAGS-}"
}

recipe_install() {
	install -D -m 0755 "$SRC/netcat-openbsd-debian-latest/nc" "$PKGDEST/usr/bin/nc"
	install -D -m 0644 "$SRC/netcat-openbsd-debian-latest/nc.1" \
		"$PKGDEST/usr/share/man/man1/nc.1"
}

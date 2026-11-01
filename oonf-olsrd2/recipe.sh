#!/bin/sh

pkgname=oonf-olsrd2
pkgver=0.15.1
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='OLSRv2 routing agent (OONF OLSR.org Network Framework)'
license='BSD-3-Clause'
origin=oonf-olsrd2
repo=saphira
url=https://github.com/OLSR/OONF
source=https://github.com/OLSR/OONF/archive/refs/tags/v0.15.1.tar.gz
sha256=9e25331fed34c2319defa29f19252b4871650c291cb97f1be067ba631e6c8b00

# Recon verdict (2026-09-10): upstream master is 187 commits ahead of the
# v0.15.1 tag, but the drift is routine maintenance (docs, DLEP fixes,
# debugging) with no rewrite or API break. Saphira pins the stable tag:
# reproducible release artifact over a moving target. Re-evaluate master
# only if the tag proves deficient (a pinned commit hash would then be
# the reproducible form, never a floating branch).
# Privilege model (verified in src/olsrd2/CMakeLists.txt): OONF_NEED_ROOT
# is true - olsrd2 refuses to run without root (route/netlink control).
# No service identity applies; both service units run it as root.
# Crypto plugins stay off exactly as upstream ships them (commented out
# in src-plugins/CMakeLists.txt), so no libtomcrypt dependency exists.
# libuci/OpenWrt plugins are not built (Saphira is not OpenWrt).
makedepends="
    cmake
    gcc
    libnl-dev
    make
    ninja
    pkgconf
"

# files/ patches (applied explicitly, mdadm idiom):
# - 0001-musl-msghdr-designated-initializers: musl msghdr has
#   __pad1/__pad2 on 64-bit LE; positional initializers mis-assign
#   (NULL into msg_iovlen, missing __pad2).
# - 0002-rfc5444-enum-result-declarations: definitions return
#   enum rfc5444_result, declarations said int (enum-int-mismatch).
# - 0003-layer2-generator-neigh-index: neighbor metadata indexed
#   with net_idx instead of neigh_idx (enum-conversion + wrong slot).
# - 0004-compare-tlvtypes-no-subtract: three-way compare without
#   signed subtraction (strict-overflow when inlined).
# - 0005-cmake-minimum-required-order: minimum-required before
#   project(), floor 2.8.12 -> 3.10 (deprecated warnings).
# - 0006-cfg-help-enum-buffer: enumerator buffer 10 -> 32 bytes
#   (holds any 64-bit idx+1, kills format-truncation).
# - 0007-ff-dat-metric-truncation: bound inner link string to 100
#   chars (128-byte buffer + " (255 hops)" suffix provably fits).
# - 0008-musl-kernel-ethhdr-guard: musl netinet/if_ether.h and kernel
#   linux/if_ether.h both define struct ethhdr; deactivate the kernel
#   copy via __UAPI_DEF_ETHHDR=0 (documented libc mechanism).
# - 0009-fno-common-log-sources: plugin _internal.h headers carry
#   tentative LOG_* definitions; -fno-common (gcc10+ default) turns
#   each including TU into its own definition and the plugin .so link
#   fails. extern in headers, single definition in the owning .c.
recipe_build()
{
	for patch in \
		0001-musl-msghdr-designated-initializers.patch \
		0002-rfc5444-enum-result-declarations.patch \
		0003-layer2-generator-neigh-index.patch \
		0004-compare-tlvtypes-no-subtract.patch \
		0005-cmake-minimum-required-order.patch \
		0006-cfg-help-enum-buffer.patch \
		0007-ff-dat-metric-truncation.patch \
		0008-musl-kernel-ethhdr-guard.patch \
		0009-fno-common-log-sources.patch; do
		patch -d "$SRC" -Np1 \
			-i "$RECIPE_DIR/files/$patch"
	done
	# gcc16: rfc5444 (msg_generator _compress_address /
	# writer_create_message, reader scheduling) trips
	# -Werror=strict-overflow on optimizer overflow assumptions.
	# Upstream logic is correct; -fno-strict-overflow disables that
	# assumption narrowly while -Werror stays intact for everything
	# else (cmake honors env CFLAGS at configure time).
	CFLAGS="${CFLAGS-} -fno-strict-overflow" \
	cmake -S "$SRC" -B "$BUILDDIR" \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX=/usr \
		-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
		-DOONF_NO_TESTING=1 \
		-DOONF_VERSION=0.15.1 \
		-DOONF_LIB_GIT=v0.15.1
	# POLICY_MINIMUM: upstream floor predates cmake 3.5 (same class
	# as musl-locales).
	# NO_TESTING: upstream cunit tests are not shipped and not run
	# here; building them trips gcc16 -Werror on test-only diagnostics.
	cmake --build "$BUILDDIR" -j${JOBS:-$(nproc)}
}

recipe_install()
{
	# Upstream names install targets per build variant
	# (install_olsrd2_{dynamic,static}); Debian ships the static one,
	# a self-contained binary with every plugin baked in. The services
	# and all docs call it olsrd2, so rename on install.
	DESTDIR="$PKGDEST" cmake --build "$BUILDDIR" --target install_olsrd2_static
	mv "$PKGDEST/usr/sbin/olsrd2_static" "$PKGDEST/usr/sbin/olsrd2"
	# Upstream manpage is section 1 under the variant name.
	install -D -m 0644 "$SRC/src/olsrd2/debian/docs/olsrd2_static.1" \
		"$PKGDEST/usr/share/man/man1/olsrd2.1"
	# Upstream ships a commented interface-template config; install it
	# as the starting point (the admin names the mesh interfaces).
	install -D -m 0644 "$SRC/src/olsrd2/debian/olsrd2.conf" \
		"$PKGDEST/etc/olsrd2/olsrd2.conf"
	install -D -m 0755 "$RECIPE_DIR/files/olsrd2.initd" \
		"$PKGDEST/etc/init.d/olsrd2"
	install -D -m 0644 "$RECIPE_DIR/files/olsrd2.service" \
		"$PKGDEST/usr/lib/systemd/system/olsrd2.service"
}

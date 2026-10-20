pkgname=saphira-linux-uapi-headers
pkgver=7.1.5
pkgrel=1
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Saphira Linux userspace UAPI headers (/usr/include; single active version per build environment)'
license=GPL-2.0-only
origin="$pkgname"
# Path-takeover handover from the retired generic name: the repo
# file-ownership gate yields /usr/include to a staged package that
# declares replaces= on the current owner (evaluate_file_collisions),
# and apk honors the same declaration at install time (clean replace
# instead of del-then-add). Without this line the first uapi publish
# collides with the still-indexed generic NVRs and can never land.
replaces="saphira-kernel-headers"
repo=main
url=https://saphira.vm2.uk/
# ONE active userspace UAPI, deliberately versioned by content: 7.1.5
# (Genesis SDK base; Egg and SAPHIRA_BUILD_SEED pin this line).
# Exactly one UAPI package is installed at a time; moving the baseline
# is a deliberate recipe edit (pkgver bump), never an automatic
# replacement — same-name upgrades replace, which is INTENDED here
# (unlike kernels, there is only ever one /usr/include).
# This replaces the retired env-selected saphira-kernel-headers, whose
# floating version silently moved Egg 7.1.5 -> 7.2.3 on upgrade.
# Kernel-module builds do NOT use this package: external modules build
# against saphira-kernel-build-headers-<kver> Kbuild trees (versioned
# /usr/src paths, co-installable). This package is host UAPI only.

depends=""

makedepends="
	gcc
	make
	perl
	rsync
"

# Upstream source is the sibling 7.1.5 kernel recipe's vendored
# tarball, read in place (never duplicated): same bytes the 7.1.5
# kernel compiles.
recipe_build()
{
	KVER=7.1.5
	KBASE="$RECIPE_DIR/../saphira-kernel-$KVER/files/linux-$KVER"
	KBALL="$KBASE.tar.xz"
	[ -f "$KBALL" ] || {
		echo "ERROR: no vendored linux-$KVER.tar.xz" >&2
		return 1
	}
	# Verify the archive against its own sidecar, without parsing it.
	(cd "$(dirname "$KBALL")" && sha256sum -c "$(basename "$KBALL").sha256") ||
		{ echo "ERROR: $(basename "$KBALL") failed its sha256 sidecar" >&2; return 1; }
	# And prove it is the SAME archive saphira-kernel-7.1.5 pins.
	kernel_sha=$(grep -m1 "^sha256=" \
		"$RECIPE_DIR/../saphira-kernel-$KVER/recipe.sh" | cut -d= -f2)
	side_sha=$(awk 'NR==1{print $1}' "$KBALL.sha256")
	[ -n "$kernel_sha" ] && [ "$kernel_sha" = "$side_sha" ] || {
		echo "ERROR: UAPI source archive does not match saphira-kernel-$KVER pin" >&2
		return 1
	}
	TREE="$BUILDDIR/tree/linux-$KVER"
	rm -rf "$BUILDDIR/tree"
	mkdir -p "$TREE"
	tar --no-same-owner -C "$TREE" --strip-components=1 -xf "$KBALL"
	[ -f "$TREE/Makefile" ] || {
		echo "ERROR: extracted tree has no Makefile: $TREE" >&2
		return 1
	}
	patch -d "$TREE" -Np1 \
		-i "$RECIPE_DIR/files/0003-libc-compat-musl-netinet-in-coordination.patch"
	make -C "$TREE" ARCH=x86_64 mrproper headers
}

recipe_install()
{
	KVER=7.1.5
	TREE="$BUILDDIR/tree/linux-$KVER"
	make -C "$TREE" ARCH=x86_64 INSTALL_HDR_PATH="$PKGDEST/usr" headers_install
	rm -f "$PKGDEST/usr/include/Makefile"
	rm -rf "$PKGDEST/usr/include/drm"
}

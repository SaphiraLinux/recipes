#!/bin/sh

pkgname=saphira-sysref
pkgver=0.1.0
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Minimal local man-page context for AI agents (MCP/CLI sysref tool)'
license='BUSL-1.1'
origin=saphira-sysref
repo=saphira
url=https://saphira.vm2.uk/
# Vendored upstream bytes (rebranded akaman 0.1.0; the tarball carries
# stale build artifacts, cleaned before build - never built from the
# checked-out tree):
akaman_sha256=3d6c8d8b38fcfb0c98d595a5f95560a2708e94002e4f690dae956d4fbb83b21f

depends=""
makedepends="
	gcc
	make
"
subpackages="$pkgname-doc"

recipe_build()
{
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$RECIPE_DIR/files/akaman-v0.1.0.tar.xz"
	cd "$SRC"
	echo "$akaman_sha256  $RECIPE_DIR/files/akaman-v0.1.0.tar.xz" | sha256sum -c -
	# Rebrand akaman -> sysref (binary, usage, conf path, man page,
	# MCP wire name). Internal akaman_run symbols and AKAMAN_*
	# preprocessor constants stay untouched (invisible internals).
	patch -Np1 -i "$RECIPE_DIR/files/0001-sysref-rename.patch"
	# Drop the tarball's stale objects/binary so our flags always apply.
	make clean
	# Saphira baseline per target arch (x86-64-v3 today; extend here
	# when new SAPHIRA_ARCH values land - fail closed otherwise).
	case "${SAPHIRA_ARCH:-x86_64}" in
		x86_64) march=-march=x86-64-v3 ;;
		aarch64) march=-march=armv8-a ;;
		*) echo "ERROR: unsupported SAPHIRA_ARCH for saphira-sysref: ${SAPHIRA_ARCH:-x86_64}" >&2; return 1 ;;
	esac
	make -j${JOBS:-$(nproc)} CC=gcc CFLAGS="-std=gnu11 -Os -Wall -Wextra $march" STATIC=0
	# Single self-check run (validation budget: the package runs its
	# proof once at build time; heavier bench/stress modes are manual).
	# No pipe: grep -q quitting early SIGPIPEs the writer under
	# pipefail and fails the build spuriously. The tool has no --help
	# flag (it prints usage with a nonzero exit), so ignore its status
	# and assert on the captured output instead.
	./akaman --help >"$BUILDDIR/help.txt" 2>&1 || true
	grep -q 'sysref QUERY' "$BUILDDIR/help.txt"
}

recipe_install()
{
	install -D -m 0755 "$SRC/akaman" "$PKGDEST/usr/bin/sysref"
	install -D -m 0644 "$SRC/docs/akaman.1" "$PKGDEST/usr/share/man/man1/sysref.1"
	# Empty 0600 config skeleton, mirroring upstream install behavior
	# under the rebranded path (APIKEY for webMCP goes here).
	install -D -m 0600 /dev/null "$PKGDEST/etc/sysref/sysref.conf"
	install -D -m 0644 "$RECIPE_DIR/files/akaman/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-sysref/LICENSE"
}

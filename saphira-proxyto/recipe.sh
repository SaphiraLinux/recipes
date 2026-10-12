#!/bin/sh

pkgname=saphira-proxyto
pkgver=0.1.0
pkgrel=8
# r8: source home moves to the SaphiraLinux/saphira-proxyto repo tag
# v0.1.0 (vendored tag bytes; stray ELF dropped). Inputs proven
# byte-identical to r7's vendored tree, but r7 is published so the
# mechanism change takes a new revision per the immutability rule.
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='PROXY-protocol front proxy for non-aware applications (geomyidae)'
license='BUSL-1.1'
origin=saphira-proxyto
repo=saphira
url=https://github.com/SaphiraLinux/saphira-proxyto
# Source home is the SaphiraLinux/saphira-proxyto repository, tag
# v0.1.0. The tag tarball is vendored in files/ (private repo: the
# builder cannot fetch it; re-verify the pin against codeload if the
# repo ever goes public). Packaging integration (units, instance
# config, identity, licence copy) stays in files/.
source=https://github.com/SaphiraLinux/saphira-proxyto/archive/refs/tags/v0.1.0.tar.gz
sha256=fc401949c504a26305a2e67e48e13f8b819d73008e51af0f55d14f0ae10e6a17

depends=""
makedepends="
	gcc
	make
"
subpackages="$pkgname-doc"

recipe_build()
{
	# The worker flattens a single top-level archive dir into $SRC,
	# so the tree root lands directly in $SRC (same as saphira-garden
	# learned the hard way). Source builds out-of-tree.
	rm -rf "$BUILDDIR/build"
	mkdir -p "$BUILDDIR/build"
	cp -r "$SRC/Makefile" "$SRC/src" "$BUILDDIR/build/"
	# Saphira baseline per target arch (x86-64-v3 today; extend here
	# when new SAPHIRA_ARCH values land - fail closed otherwise).
	case "${SAPHIRA_ARCH:-x86_64}" in
		x86_64) march=x86-64-v3 ;;
		aarch64) march=armv8-a ;;
		*) echo "ERROR: unsupported SAPHIRA_ARCH for saphira-proxyto: ${SAPHIRA_ARCH:-x86_64}" >&2; return 1 ;;
	esac
	make -C "$BUILDDIR/build" -j${JOBS:-$(nproc)} CC=gcc ARCH="$march" PREFIX=/usr
	# Upstream tests bind loopback sockets; the build sandbox may not
	# provide them, so they run on the test deployment, not here.
}

recipe_install()
{
	install -D -m 0755 "$BUILDDIR/build/proxyto" "$PKGDEST/usr/bin/proxyto"
	install -D -m 0644 "$SRC/man/proxyto.1" "$PKGDEST/usr/share/man/man1/proxyto.1"
	install -D -m 0644 "$RECIPE_DIR/files/etc/saphira/proxyto/geomyidae.conf" \
		"$PKGDEST/etc/saphira/proxyto/geomyidae.conf"
	install -D -m 0755 "$RECIPE_DIR/files/proxyto.initd" \
		"$PKGDEST/etc/init.d/proxyto"
	install -D -m 0644 "$RECIPE_DIR/files/proxyto.confd" \
		"$PKGDEST/etc/conf.d/proxyto"
	install -D -m 0644 "$RECIPE_DIR/files/proxyto.service" \
		"$PKGDEST/usr/lib/systemd/system/proxyto.service"
	install -D -m 0644 "$RECIPE_DIR/files/LICENSE" \
		"$PKGDEST/usr/share/licenses/saphira-proxyto/LICENSE"
	# Runtime identity declaration: proxyto:19 required by the compiled
	# service defaults. makepkg generates the install scripts from
	# this fragment; the package creates its identity at install time.
	# r3: fragment added (payload change, revision bumps).
	# r4: reap exited children in the SIGCHLD handler (SA_RESTART left
	#     accept() uninterruptible, so the deferred flag reap kept one
	#     zombie while idle) + regression test + document deliberate
	#     no-User= in the systemd unit.
	install -D -m 0644 "$RECIPE_DIR/files/accounts.d/saphira-proxyto" \
		"$PKGDEST/usr/share/saphira/accounts.d/saphira-proxyto"
}

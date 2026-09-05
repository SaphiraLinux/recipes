#!/bin/sh

pkgname=musl
pkgver=1.2.6
pkgrel=2
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='musl libc 1.2.6 with the Saphira 1MiB pthread stack patch - the installable base libc'
license='MIT'
origin=musl
repo=saphira
url=https://musl.libc.org/
# Vendored from keeper build tree (verified bytes):
#   homer:/tank/saphira-builder/musl-master-saphira-build/pkg/musl-1.2.6.tar.gz
musl_sha256=e9db8b70b0cba3db43b27e84ccd8a0c0958b40029a1c36c9f13817b93787b4d6
# Saphira policy patch (MEGA IMPORTANT, AGENTS/memory rule):
#   DEFAULT_STACK_SIZE 131072 -> 1048576 (1MiB), guard 8192 unchanged.
#   This patch MUST accompany every musl-libc APK we ever build.
musl_patch_sha256=e74dcb8dd4aaf6bf9ad1410a3394343bbfbfb34e55007c83fe2b63dccc5767cc
# Kernel UAPI coordination: netinet/in.h skips IPv6 structures when
# linux/in6.h was included first (mirrors glibc __USE_KERNEL_IPV6_DEFS).
# Fixes packages mixing <netinet/in.h> with kernel netfilter headers.
in6_patch_sha256=28ea1e653d0b4e242065714c2018aed67d68ce06dc5cd8526ef735a1a5a06d01

depends=""
makedepends="
	binutils
	gcc
	make
"

subpackages="$pkgname-dev"

recipe_build()
{
	MBALL="$RECIPE_DIR/files/musl-1.2.6.tar.gz"
	echo "$musl_sha256  $MBALL" | sha256sum -c -
	PB="$RECIPE_DIR/files/0001-default-pthread-stack-1MiB.patch"
	echo "$musl_patch_sha256  $PB" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$MBALL"
	patch -d "$SRC" -Np1 -i "$PB"
	P6="$RECIPE_DIR/files/0002-netinet-in6-kernel-uapi-coordination.patch"
	echo "$in6_patch_sha256  $P6" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P6"
	cd "$SRC"
	# Built against the generation-zero musl headers already present in
	# the clean root: same-ABI rebuild, no cross toolchain involved.
	./configure --prefix=/usr --syslibdir=/lib
	make -j${JOBS:-$(nproc)}

	# Generation-zero parity check: compare the freshly built dynamic
	# loader and libc against the bootstrap copies this clean root runs
	# from (staged via bootstrap-v0.1.paths). Differences are REPORTED,
	# never hidden - this package is for clean v0.2 bases, and must not
	# be blindly installed over a running system.
	for f in lib/libc.musl-x86_64.so.1 lib/ld-musl-x86_64.so.1; do
		src="$SRC/lib/$(basename "$f")"
		[ -f "$src" ] || src="/$f"
		if [ -f "/$f" ]; then
			if cmp -s "$src" "/$f"; then
				echo "parity: $f matches generation-zero"
			else
				echo "parity: $f DIFFERS from generation-zero (expected for rebuild; do not overwrite running systems with this)"
			fi
		else
			echo "parity: no generation-zero /$f in this root to compare"
		fi
	done
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
}

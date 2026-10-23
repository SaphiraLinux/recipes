#!/bin/sh

pkgname=musl
pkgver=1.2.6
# r3: static-PIE foundation repair. The static libc archive is now
# assembled from musl's existing PIC object family (AOBJS = LOBJS via
# config.mak override, per the Makefile's own "use config.mak to
# override" contract) so libc.a links into static-PIE binaries.
# Shared libc, loader, CRT, headers and ABI are intentionally
# unchanged: libc.so keeps consuming the same LOBJS as before.
# r4->r5 carries only the utmp/wtmp paths.h statements (no code,
# no ABI): direct-file readers resolve the real database.
# r6: extend 0003 to utmp.h (2026-10-23, proven by openssh r4:
# paths.h alone does not move WTMP_FILE/UTMP_FILE, and configure
# CONF_* overrides are dead whenever the macros exist -- the header
# is the single source of truth, so it carries the real paths too).
# Headers only, no code, no ABI.
pkgrel=6
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
# Stage4 utmp integration: libc paths.h points _PATH_UTMP/_PATH_WTMP
# at the real database locations (/var/run/utmp, /var/log/wtmp)
# instead of musl upstream's /dev/null placeholders. Saphira writes
# real accounting there (saphira-utmp-boot); direct-file readers
# such as util-linux last then work. This changes no ABI and no
# libc behavior: musl's getutxent remains upstream-stubbed, so
# coreutils who/uptime keep using their fallbacks, which is exactly
# what makes uptime correct once no stale seed shadows the lookup.
utmp_patch_sha256=e8eab82e03d975af6d0dbd33af878e85dbe5909059c8871248868bd7fc7b11a6

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
	P7="$RECIPE_DIR/files/0003-utmp-wtmp-real-paths.patch"
	echo "$utmp_patch_sha256  $P7" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P7"
	cd "$SRC"
	# Built against the repository musl-dev headers installed in the
	# clean root from the package seed: same-ABI rebuild, no cross
	# toolchain and no host files involved.
	./configure --prefix=/usr --sysconfdir=/etc --syslibdir=/lib --localstatedir=/var
	# Saphira policy: the static libc archive must support static PIE.
	# Reuse musl's existing PIC libc object set (LOBJS, built with
	# -fPIC for libc.so) instead of the default non-PIC AOBJS.
	# Verified against vendored 1.2.6: Makefile line 7 invites
	# config.mak overrides, line 78 includes it after the defaults,
	# line 132 compiles LOBJS with -fPIC, line 165 archives AOBJS.
	printf '%s\n' \
		'# Saphira policy: libc.a must be static-PIE capable.' \
		'AOBJS = $(LOBJS)' >> config.mak
	make -j${JOBS:-$(nproc)}

	# Policy assert: every object in the static archive must be
	# static-PIE capable (no absolute 32-bit relocations). Scans the
	# actual archive that ships, not just the build tree.
	rm -rf "$SRC/obj/piecheck" && mkdir -p "$SRC/obj/piecheck"
	(cd "$SRC/obj/piecheck" && ar x "$SRC/lib/libc.a") || {
		echo "ERROR: cannot extract lib/libc.a for PIE check" >&2
		return 1
	}
	if readelf -r "$SRC/obj/piecheck"/* 2>/dev/null |
		grep -E 'R_X86_64_32([^0-9]|$)'; then
		echo "ERROR: libc.a contains non-PIC objects (absolute 32-bit relocations)" >&2
		rm -rf "$SRC/obj/piecheck"
		return 1
	fi
	rm -rf "$SRC/obj/piecheck"
	echo "piecheck: libc.a is static-PIE capable"

	# Self-hosting parity check: compare the freshly built dynamic
	# loader and libc against the repository copies this clean root
	# runs from. Differences are REPORTED, never hidden - this package
	# is for clean v0.2 bases, and must not be blindly installed over
	# a running system.
	for f in lib/libc.musl-x86_64.so.1 lib/ld-musl-x86_64.so.1; do
		src="$SRC/lib/$(basename "$f")"
		[ -f "$src" ] || src="/$f"
		if [ -f "/$f" ]; then
			if cmp -s "$src" "/$f"; then
				echo "parity: $f matches repository seed"
			else
				echo "parity: $f DIFFERS from repository seed (expected for rebuild; do not overwrite running systems with this)"
			fi
		else
			echo "parity: no repository-seeded /$f in this root to compare"
		fi
	done
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
	# musl upstream ships no ldd(1): the dynamic loader itself serves as
	# one via --list. Ship the conventional wrapper owned by this package
	# so clean roots get a working ldd with no handmade symlinks.
	# Absolute loader path: no PATH lookup, no usrmerge assumption, and
	# it keeps working when /usr is not yet mounted.
	install -d -m 0755 "$PKGDEST/usr/bin"
	cat > "$PKGDEST/usr/bin/ldd" <<'EOF'
#!/bin/sh
exec /lib/ld-musl-x86_64.so.1 --list "$@"
EOF
	chmod 0755 "$PKGDEST/usr/bin/ldd"
}

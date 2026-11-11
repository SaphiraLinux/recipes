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
# r8: integrate validated Saphira arch optimisations onto the r7
# RC-69 base (reconcile/musl-r7-sinew): 0004 rint/rintf + F3
# floor/ceil/trunc/nearbyint (0008-0012) + F8 strstr (0014).
# New arch files + two modified files (rint.c/rintf.c from 0004,
# strstr.c wiring); RC-69 untouched and applied first.
pkgrel=8
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
# Saphira arch optimisations (validated on exp/musl-f8-strstr @93f0d39b,
# byte-identical files replayed here; 0004 from exp/musl-r8 @d465def8
# lineage, required base for 0011). SSE4.1 roundsd/roundss (floor/ceil/
# trunc/rint/nearbyint, MXCSR-mode, DAZ-gated cold paths, flag parity)
# + SSE2 strstr 2/3/4-byte helpers (hidden syms, generic kept).
# Rejected F6 (0013 AVX2 mbsrtowcs: correct but slower) and unapproved
# F5 are deliberately NOT carried.
rint_patch_sha256=f5b27c7dac830a02985685337cbca2ddb32ffcbdb7eccf79b0e7a070d17da5c5
floor_patch_sha256=7bbc00ffae9ef528872e0e4caf507574e5b5a00cd558ee03d9e46d09d4f0ad8e
ceil_patch_sha256=0373f2d97238b1a99841b2778a6ee7bb0a6d2350a22fb7dfe436c9ef8ab80501
trunc_patch_sha256=27205918544f6aa6fae2ec1ba4c7c325fa5da2a0173a8c351ccdc46702fe0285
rint_realop_patch_sha256=24b768fb16cb26ca9d032b32e65c35d107b2254cc732293097bc46b11d662147
nearbyint_patch_sha256=d7331d5f7259f85e24915160c78209d95f4d4f26afee4367e840fdb92b68946c
strstr_sse2_patch_sha256=7e1345773f9fe05519d3b09b31f9e89e8e51e9ba703555be66d590a8e382a563

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
	# Upstream corrective backports 0101..0170 (minus deferred 0130),
	# pinned by files/UPSTREAM-SHA256SUMS, applied in filename order
	# (topological). See files/PATCHES.md for per-patch rationale and
	# files/AUDIT-SERIES.md for the audit evidence behind each one.
	(cd "$RECIPE_DIR/files" && sha256sum -c UPSTREAM-SHA256SUMS) || return 1
	for up in "$RECIPE_DIR"/files/01[0-9][0-9]-upstream-*.patch; do
		patch -d "$SRC" -Np1 -i "$up"
	done
	# Saphira arch optimisations 0004 + 0008-0012 + 0014 (pins above).
	# Applied after RC-69; file sets are disjoint from RC-69 (verified:
	# no RC-69 patch touches these paths), so the result matches the
	# validated exp tree. 0011 modifies the 0004 files: order matters.
	# Drop this block to restore pure r7 behaviour.
	PS="$RECIPE_DIR/files/0004-x86_64-rint-roundsd.patch"
	echo "$rint_patch_sha256  $PS" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$PS"
	P12="$RECIPE_DIR/files/0008-x86_64-floor-roundsd.patch"
	echo "$floor_patch_sha256  $P12" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P12"
	P13="$RECIPE_DIR/files/0009-x86_64-ceil-roundsd.patch"
	echo "$ceil_patch_sha256  $P13" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P13"
	P14="$RECIPE_DIR/files/0010-x86_64-trunc-roundsd.patch"
	echo "$trunc_patch_sha256  $P14" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P14"
	P15="$RECIPE_DIR/files/0011-x86_64-rint-realop-denormal.patch"
	echo "$rint_realop_patch_sha256  $P15" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P15"
	P16="$RECIPE_DIR/files/0012-x86_64-nearbyint-roundsd.patch"
	echo "$nearbyint_patch_sha256  $P16" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P16"
	P17="$RECIPE_DIR/files/0014-x86_64-strstr-sse2-short-needle.patch"
	echo "$strstr_sse2_patch_sha256  $P17" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P17"
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

#!/bin/sh
# musl 1.2.6_p1-r1 — sinew lineage (test revision, hatchling validation).
#
# This recipe IS musl (pkgname musl): it supersedes the published
# 1.2.6-r8. The previous r7 recipe is preserved untouched at
# /recipes/musl.disabled for reference. Foundation is byte-identical
# musl 1.2.6 (vendored ball files/musl-1.2.6.tar.gz, sha256
# e9db8b70b0cba3db43b27e84ccd8a0c0958b40029a1c36c9f13817b93787b4d6,
# verified against upstream v1.2.6 tag) plus Saphira patches 0001-0003,
# upstream corrective backports 0101..0170 (minus deferred 0130, pinned
# by files/UPSTREAM-SHA256SUMS), the validated arch rint/rintf
# optimisation as 0004 (promoted from exp/musl-r8 @9fd47a9; evidence:
# 2.16M differential + 1M MPFR, 0 fails; F2 catalog in sinew tests),
# and the F3 floor-family series 0008-0011 (floor/ceil/trunc arch +
# rint real-op denormal handling; checkpoint 92; validation evidence
# in musl/tests/f3-work/).
#
# Version identity is dual: musl's compatible package version (what APK
# understands) and Sinew's independent implementation version below.
# 1.2.6_p1 sorts newer than published 1.2.6-r8 (verified: apk
# version -t says >), so `apk upgrade` adopts it as an ordinary
# same-name upgrade. pkgrel restarts at 1 on the new _p1 line;
# bumppkg owns all future transitions (pkgver must always begin with
# a digit: apk rejects anything else, and the gate NVR regex requires
# it — sinew.1.2.6 was proven uninstallable, checkpoint 78).
#
# Compatibility contract (binding):
# - Keep the x86_64-akadata-linux-musl compiler target. No
#   GCC/binutils/Clang/Rust change here.
# - Keep the musl ABI and exported symbol contract (1650 symbols,
#   additive changes only).
# - Keep /lib/ld-musl-x86_64.so.1 as the ELF interpreter and the
#   existing /lib + /usr/include layout, CRT, TLS, pthread and
#   static-PIE behaviour.
# - Same package name as the published libc: installation is an
#   ordinary version upgrade (no replaces/provides/conflicts
#   metadata, no second libc, no overlapping ownership by design).
#   Test publication goes to hatchling first; hatched promotion only
#   on explicit validation GO.

pkgname=musl
pkgver=1.2.6_p1
# Sinew implementation version (independent release history; the
# musl-compatible package version above is what APK orders on).
_sinew_version=0.1.0
# New _p1 line, so pkgrel restarts at 1 (it must still sort above
# every 1.2.6-rN: verified > r8 via apk version -t).
pkgrel=5
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Sinew libc — Saphira'"'"'s musl-compatible C library'
license='MIT'
origin=musl
repo=saphira
url=https://musl.libc.org/
# Foundation ball is byte-identical to Saphira musl 1.2.6
# (keeper build tree verified bytes):
#   homer:/tank/saphira-builder/musl-master-saphira-build/pkg/musl-1.2.6.tar.gz
musl_ball_sha256=e9db8b70b0cba3db43b27e84ccd8a0c0958b40029a1c36c9f13817b93787b4d6
# Saphira policy patch (MEGA IMPORTANT):
#   DEFAULT_STACK_SIZE 131072 -> 1048576 (1MiB), guard 8192 unchanged.
#   This patch MUST accompany every libc APK we ever build.
musl_stack_sha256=e74dcb8dd4aaf6bf9ad1410a3394343bbfbfb34e55007c83fe2b63dccc5767cc
# Kernel UAPI coordination (inherited from musl 0002).
in6_patch_sha256=28ea1e653d0b4e242065714c2018aed67d68ce06dc5cd8526ef735a1a5a06d01
# Stage4 utmp integration (0003, headers only).
utmp_patch_sha256=e8eab82e03d975af6d0dbd33af878e85dbe5909059c8871248868bd7fc7b11a6
# Sinew-lineage optimisation (promoted from exp/musl-r8):
# arch rint/rintf via SSE4.1 roundsd/roundss + DE-bit preservation.
rint_patch_sha256=f5b27c7dac830a02985685337cbca2ddb32ffcbdb7eccf79b0e7a070d17da5c5
# EXPERIMENTAL strncmp/memcmp (independent; drop either freely).
strncmp_patch_sha256=be76e9d667157364819089eeedc0824b7bc42e1025f680871bc96bdd0fdd3b3c
memcmp_patch_sha256=8ecdce7e87c156aa47b0d21b2890bbaf0033ccb8a28a3837c7bf090fa8aa0759
# EXPERIMENTAL (exp/musl-r8 only): arch memmove backward path via
# SSE2 16-byte blocks (Parker Loflin 31-Oct proposal; evidence:
# 564450 checks x 5 hosts, 0 fails; backward 10-21x, forward 1.00x).
# Generic C stays untouched as reference. Drop this block and the
# 0005 patch to restore pure _p1 behaviour.
memmove_patch_sha256=4ded70ad91844e99c332a16a043ec84b20694daf70b5cb705e601fe55c00a644
# F3 floor-family optimisation (exp/musl-r8 only; checkpoint 92):
# arch floor/floorf, ceil/ceilf, trunc/truncf via SSE4.1
# roundsd/roundss suppress + DAZ-gated cold path (truth in both DAZ
# modes; sacrificial orig+1.0 real op for flag/trap fidelity).
# 0011 replaces the 0004 ldmxcsr DE-restore with the same real-op
# mechanism (ldmxcsr never traps; the real op preserves DM-trap
# behaviour). Generic C stays as numerical reference (REPLACED_OBJS).
# Evidence: 388224-case masked differential ffails=0 (D1 PE-silence,
# D3 sNaN-IE, policy-4 FTZ-UE classified); DM trap parity all 8 fns;
# UM/PM/IM divergences documented per operator trap policy.
floor_patch_sha256=7bbc00ffae9ef528872e0e4caf507574e5b5a00cd558ee03d9e46d09d4f0ad8e
ceil_patch_sha256=0373f2d97238b1a99841b2778a6ee7bb0a6d2350a22fb7dfe436c9ef8ab80501
trunc_patch_sha256=27205918544f6aa6fae2ec1ba4c7c325fa5da2a0173a8c351ccdc46702fe0285
rint_realop_patch_sha256=24b768fb16cb26ca9d032b32e65c35d107b2254cc732293097bc46b11d662147
# F4 nearbyint optimisation (exp/musl-f4-nearbyint only; checkpoint 98/99):
# arch nearbyint/nearbyintf (0012, new src/math/x86_64/*.s, one function
# per TU) via SSE4.1 roundsd/roundss suppress ($0x0C, MXCSR mode) +
# DAZ-gated cold path with ucomisd DE-only flag restoration. Masked
# flags bit-identical to generic; inexact never raised (contract).
nearbyint_patch_sha256=d7331d5f7259f85e24915160c78209d95f4d4f26afee4367e840fdb92b68946c
# F8 strstr short-needle optimisation (release candidate r5):
# arch 2/3/4-byte needle helpers (0014, new src/string/x86_64/*.s, hidden
# symbols) + strstr.c wiring (generic bodies kept under #else). SSE2
# equality-mask windows, page-bounded loads; 1B path and >=5B two-way
# untouched. Drop file + block to revert to generic strstr.
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
	echo "$musl_ball_sha256  $MBALL" | sha256sum -c -
	PB="$RECIPE_DIR/files/0001-default-pthread-stack-1MiB.patch"
	echo "$musl_stack_sha256  $PB" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$MBALL"
	patch -d "$SRC" -Np1 -i "$PB"
	P6="$RECIPE_DIR/files/0002-netinet-in6-kernel-uapi-coordination.patch"
	echo "$in6_patch_sha256  $P6" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P6"
	P7="$RECIPE_DIR/files/0003-utmp-wtmp-real-paths.patch"
	echo "$utmp_patch_sha256  $P7" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P7"
	# First independent Sinew optimisation: arch rint/rintf.
	P8="$RECIPE_DIR/files/0004-x86_64-rint-roundsd.patch"
	echo "$rint_patch_sha256  $P8" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P8"
	# EXPERIMENTAL (exp/musl-r8 only): arch memmove backward path.
	P9="$RECIPE_DIR/files/0005-x86_64-memmove-sse2-backward.patch"
	echo "$memmove_patch_sha256  $P9" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P9"
	# EXPERIMENTAL (exp/musl-r8 only): arch strncmp/memcmp via SSE2.
	# Independent patches so each can be dropped separately.
	P10="$RECIPE_DIR/files/0006-x86_64-strncmp-sse2.patch"
	echo "$strncmp_patch_sha256  $P10" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P10"
	P11="$RECIPE_DIR/files/0007-x86_64-memcmp-sse2.patch"
	echo "$memcmp_patch_sha256  $P11" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P11"
	# F3 (exp/musl-r8 only): arch floor/ceil/trunc families + rint
	# real-op denormal handling. Independent patches; 0011 modifies
	# the 0004 files so it applies last. Drop all four + this block
	# to restore pre-F3 behaviour (0004 rint stays).
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
	# F4 (exp/musl-f4-nearbyint only): arch nearbyint/nearbyintf.
	P16="$RECIPE_DIR/files/0012-x86_64-nearbyint-roundsd.patch"
	echo "$nearbyint_patch_sha256  $P16" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P16"
	# F8 (release candidate r5): arch strstr 2/3/4-byte needle helpers.
	P17="$RECIPE_DIR/files/0014-x86_64-strstr-sse2-short-needle.patch"
	echo "$strstr_sse2_patch_sha256  $P17" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P17"
	# Upstream corrective backports 0101..0170 (minus deferred 0130),
	# pinned by files/UPSTREAM-SHA256SUMS, applied in filename order
	# (topological). Same RC-69 series as r7; see PATCHES.md for
	# per-patch rationale and provenance.
	(cd "$RECIPE_DIR/files" && sha256sum -c UPSTREAM-SHA256SUMS) || return 1
	for up in "$RECIPE_DIR"/files/01[0-9][0-9]-upstream-*.patch; do
		patch -d "$SRC" -Np1 -i "$up"
	done
	cd "$SRC"
	# Same configure baseline as r7: non-usrmerged layout,
	# syslibdir /lib keeps the loader at /lib/ld-musl-x86_64.so.1.
	./configure --prefix=/usr --sysconfdir=/etc --syslibdir=/lib --localstatedir=/var
	# Saphira policy: the static libc archive must support static PIE.
	# Reuse musl's existing PIC libc object set (LOBJS) instead of the
	# default non-PIC AOBJS (Makefile invites config.mak overrides).
	printf '%s\n' \
		'# Saphira policy: libc.a must be static-PIE capable.' \
		'AOBJS = $(LOBJS)' >> config.mak
	make -j${JOBS:-$(nproc)}

	# Policy assert: every object in the static archive must be
	# static-PIE capable (no absolute 32-bit relocations).
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

	# Parity report: r8 artifacts are expected to differ from the
	# published r7 seed exactly in rint/rintf objects (arch
	# roundsd/roundss). Differences are REPORTED, never hidden.
	for f in lib/libc.musl-x86_64.so.1 lib/ld-musl-x86_64.so.1; do
		src="$SRC/lib/$(basename "$f")"
		[ -f "$src" ] || src="/$f"
		if [ -f "/$f" ]; then
			if cmp -s "$src" "/$f"; then
				echo "parity: $f matches live seed"
			else
				echo "parity: $f DIFFERS from live seed (expected for r8 rint objects)"
			fi
		else
			echo "parity: no live /$f in this root to compare"
		fi
	done
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
	# musl upstream ships no ldd(1): the dynamic loader itself serves as
	# one via --list. Ship the conventional wrapper owned by this package
	# so clean roots get a working ldd with no handmade symlinks.
	install -d -m 0755 "$PKGDEST/usr/bin"
	cat > "$PKGDEST/usr/bin/ldd" <<'EOF'
#!/bin/sh
exec /lib/ld-musl-x86_64.so.1 --list "$@"
EOF
	chmod 0755 "$PKGDEST/usr/bin/ldd"
}

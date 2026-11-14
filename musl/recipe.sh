#!/bin/sh
# musl 1.2.6_p1-r1 — sinew lineage (test revision, hatchling validation).
#
# This recipe IS musl (pkgname musl): it supersedes the published
# 1.2.6-r8. The previous r7 recipe is preserved untouched at
# /recipes/musl.disabled for reference. Foundation is byte-identical
# musl 1.2.6 (vendored ball files/musl-1.2.6.tar.gz, sha256
# e9db8b70b0cba3db43b27e84ccd8a0c0958b40029a1c36c9f13817b93787b4d6,
# verified against upstream v1.2.6 tag) plus Saphira patches 0001-0003,
# upstream corrective backports 0101..0171 (minus deferred 0130, pinned
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
pkgrel=21
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
# Sinew clone3 raw primitive (sinew/foundation step 7): new
# src/linux/clone3.c, internal __clone3 only (hidden, no public
# declaration). Drop file + block to remove it entirely.
clone3_patch_sha256=9fd33f5edff7e7af60b4551034fe0748539cb5bf8591a018ce6821956f586542
# Saphira wordexp WRDE_NOCMD hardening (bugs/wordexp-nocmd-bypass.md):
# comment-awareness, ANSI-C quote tracking, $(( )) arithmetic
# validation, ${...} opaque skipping. Drop file + block to revert.
wordexp_nocmd_patch_sha256=d56eacb6f49e442de554cc0491c6b67fb55bd86ffec87b1159d4b36b57f27af0
# powf y==1 exact fast path (bugs/powf-y1-spurious-flags.md):
# exact result, no spurious flags; sNaN still signals via x+y.
powf_y1_patch_sha256=af7884a0f21a02561525f5fc8cfa615c04b3a33a424fad6792c253c5f2e6b695
# strptime %z hours-only form (bugs/strptime-z-hours-only.md):
# accept ±HH in addition to ±HHMM (no colon form).
strptime_z_patch_sha256=208f8d3320cc1cbd9d0331ea72dfecf35f9c714c162ddca163bbd7263ef6ba9a
# strptime %s epoch conversion: convert signed Unix epoch seconds to
# calendar fields via __localtime_r (glibc local-time semantics; POSIX
# leaves the effect unspecified). Deliberate Sinew deltas vs glibc:
# '-' accepted for pre-epoch values; overflow/time_t-range/year-range
# fail closed instead of wrapping.
strptime_s_patch_sha256=8cf061f7e2d31129d1da1a96c8439f5ce61cf64031ec930c028a063672634491
# wordexp WRDE_UNDEF: forkless pre-expansion check for attempts to
# expand unset variables (BADVAL without forking, hence zero command
# side effects). Preserves NOCMD-scanner precedence; passes through
# anything ambiguous (fail-open provisional, not conformance proof).
undef_check_patch_sha256=995b1eef5f3d5cae736459e9d1e8540cf4353f4a8b2a6d636d625db88e47878e
# wordexp Class-B parameter parser: quoted-context brace words
# re-tokenize with a fresh quote state and distinguish quote-first
# "$" (transparent, exposes the following token) from dollar-first
# $" (locale string, content still expands). Fixes the 64-65
# false negative without flagging legitimate locale expressions;
# arithmetic digit-led tokens are numbers, never variables.
classb_quotes_patch_sha256=192bb04789b23b81e2fa926ca9a7da265e7ae087491effbe826684a07082cec3
# wordexp NOCMD nested-brace hardening (Sinew 0022): brace_unit takes
# the enclosing double-quote context (top-level scan passes its dq,
# nested braces pass current dq, arithmetic passes 0); a
# single-quoted region opened under outer dq does NOT suppress
# $(...) or backquote detection; blocked arithmetic (ar==1)
# propagates CMDSUB instead of being scanned as literal text;
# a bare } inside arithmetic is malformed, not blocked.
nocmd_nested_patch_sha256=525a5f0d3eabd4001c30123ff8f24133a6f172a2e14d663d8c10311cb87403be
# wordexp arithmetic close + quotes (Sinew 0023): arithmetic is only
# valid when the two closing parens are adjacent (a spaced close is
# parsed as $(...) command substitution by the shell, verified
# 2026-11-12); double-quoted spans inside arithmetic expand (their
# content is still scanned: $(...)/backquote blocks, ${...} recurses
# in quoted context); a bare { in a brace word is literal (the shell
# expands ${X-{}} to {}). Closes a missed NOCMD execution (spaced
# close) with zero regressions.
arith_close_quotes_patch_sha256=2fe500c65ac48cda52c38f05bfaba48bb770fc25596fb5b4f6d98faaea7051d4
# fmal subnormal underflow (Sinew 0024): the TONEAREST denormal path
# scales exactly, so it never raises underflow itself; when the result
# is tiny and inexactness was observed, underflow is due (mirrors the
# directed-mode tail). Fixes the suite fmal.h:46 missing UNDERFLOW
# with zero other flag/value changes across the full fmal tables.
fmal_underflow_patch_sha256=209bdd517e516352c65f6d7c63040995be86f530f67e7e7e36fa7949ce0e3715
# wordexp ANSI-C quoting context (Sinew 0025): $'...' is genuine ANSI
# only outside arithmetic and double quotes (the shell reads $ and '
# literally inside either, so embedded $(...)/backquote runs there).
# Genuine-position spans with cmdsubst text no longer block (corpus
# vec-23 now expands like the shell and glibc); dq/arith positions
# still block exactly as before.
ansi_quoting_patch_sha256=c8f7533a51a3d9916ba8c14364a0a0745608094de2bba46e04394ef71f59b3ab
# regex backref multibyte resync (Sinew 0026): the backtracking matcher
# assumed one-byte positions in five places (retry advance, pop restore,
# backref compare base/advance, EOS check used the stale read head).
# Multibyte input silently skipped start positions, compared inside
# characters and desynchronised pos/str_byte. Fixes both suite backref
# failures with zero changes on single-byte behaviour (differentially
# proven identical) and glibc-identical verdicts on all fuzz deltas.
regex_backref_mb_patch_sha256=bef68736877448ba2202cc3b46ad92584bb4bf0c93bd606e254ec11fd65eca0a
# fnmatch audit residuals (Sinew 0027): hyphen after a consumed range is
# literal (POSIX XBD 9.3.5 partial-range rule; fixes [a-c-e] chaining
# false positive/negative), PATHNAME splitter returns NOMATCH on
# uninterpretable pattern bytes (fixes UTF-8-locale unbounded loop).
fnmatch_audit_patch_sha256=70f64aecbb2ba04a73eba5bc71719d6d908cf44075fb99c0b2b963d9d7a365f2
# scanf multi-digit positional (Sinew 0028): %n$ accepts multi-digit N
# (POSIX requires decimal integer; single-digit-only was fmt_fail).
scanf_positional_patch_sha256=356df39d26e268374d1c4af25beeb812b94727f2d6b244cacb175270a3a899ba
# scanf short-%c input failure (Sinew 0029): EOF before width completes
# is input failure, not matching failure (POSIX return-value rule).
scanf_short_input_patch_sha256=0dfcae7e6795060a498cb8fc38b015de9f1bea5e077701920c0d364439294338
# scanf wide-%c character counting (Sinew 0030): wide %c counts
# complete characters, not bytes (POSIX sequence-of-characters rule).
scanf_wide_count_patch_sha256=7a04202990fa1926ac5b8620553eed5d9a876fb7ad0bfcda1e57e97fdb3a57fd
# swscanf wide-input adapter (Sinew 0031 WN4): locale-independent
# UTF-8 encoder plus C.UTF-8 stream pin (POSIX wide-input rule).
swscanf_wide_adapter_patch_sha256=7a585d183953bb616fe90871b451dd96f03ff23b0b9ac25c336f1f8a9f6e40fb
# floatscan nan sign (Sinew 0032): __floatscan returns sign-applied
# quiet NaN (POSIX "negated" rule; INFINITY path already applies sign).
# sign*NAN is a proven no-op (NaN arithmetic keeps the operand sign),
# so the ternary folds -NAN correctly. Touches NaN paths only.
nan_sign_patch_sha256=a8ea20789e36555a818ae4fb0092c5b6d156a472a5eb5d6e7f030082de0aab0e
# wordexp NOCMD close-quote (Sinew 0033): brace_unit treats "$(" as
# live command substitution when the quote may close (in_dq or
# arithmetic context), validating ((...)) via arith_ok; S6q bypass
# executed despite WRDE_NOCMD. Touches the NOCMD pre-scan only.
nocmd_close_quote_patch_sha256=c21ddf3b81e5217b439be6465227a6d733e019e930e03a4140110e221f501f31
# mallocng huge-overalignment (Sinew 0034): aligned_alloc returns the
# unneeded tail pages when headroom over 2GB would truncate set_size's
# int reservation and the u32 tail field (2^34 SIGSEGV, layout
# dependent). Complements upstream 0114 (get_meta offset width).
# Touches aligned_alloc only; size-class paths cannot reach it.
huge_align_patch_sha256=7d08bf676ec0791a3185716f31a2ce83008a59cb742c9d7f8022d79415b4f6ff

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
	# Sinew clone3 raw primitive (sinew/foundation step 7): new
	# src/linux/clone3.c only; no existing files touched.
	P18="$RECIPE_DIR/files/0015-sinew-clone3-raw-primitive.patch"
	echo "$clone3_patch_sha256  $P18" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P18"
	# Saphira wordexp WRDE_NOCMD hardening: comment-awareness,
	# ANSI-C quote tracking, arithmetic validation, ${...} skipping.
	P19="$RECIPE_DIR/files/0016-saphira-wordexp-nocmd-scan.patch"
	echo "$wordexp_nocmd_patch_sha256  $P19" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P19"
	# powf y==1 exact fast path (bugs/powf-y1-spurious-flags.md).
	P20="$RECIPE_DIR/files/0017-saphira-powf-y1-exact.patch"
	echo "$powf_y1_patch_sha256  $P20" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P20"
	# strptime %z hours-only form (bugs/strptime-z-hours-only.md).
	P21="$RECIPE_DIR/files/0018-saphira-strptime-z-hours.patch"
	echo "$strptime_z_patch_sha256  $P21" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P21"
	# Upstream corrective backports 0101..0171 (minus deferred 0130),
	# pinned by files/UPSTREAM-SHA256SUMS, applied in filename order
	# (topological). Same RC-69 series as r7; see PATCHES.md for
	# per-patch rationale and provenance.
	(cd "$RECIPE_DIR/files" && sha256sum -c UPSTREAM-SHA256SUMS) || return 1
	for up in "$RECIPE_DIR"/files/01[0-9][0-9]-upstream-*.patch; do
		patch -d "$SRC" -Np1 -i "$up"
	done
	# strptime %s epoch conversion. Applied after upstream so its
	# context matches 0104 (which adds the time_impl.h include).
	P22="$RECIPE_DIR/files/0019-saphira-strptime-s-epoch.patch"
	echo "$strptime_s_patch_sha256  $P22" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P22"
	# WRDE_UNDEF forkless check. Applied after upstream so its
	# context matches 0138/0153/0154 (same files it was verified on).
	P23="$RECIPE_DIR/files/0020-saphira-wordexp-undef-forkless.patch"
	echo "$undef_check_patch_sha256  $P23" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P23"
	# Class-B parameter parser (quoted-context brace words, quote-first
	# vs dollar-first $" rule, arithmetic numbers). Applied after 0020
	# (extends its undef_* functions).
	P24="$RECIPE_DIR/files/0021-saphira-wordexp-classb-quotes.patch"
	echo "$classb_quotes_patch_sha256  $P24" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P24"
	# NOCMD nested-brace hardening (Sinew 0022): entry-dq threading
	# plus blocked-arithmetic propagation. Applied after 0021.
	P25="$RECIPE_DIR/files/0022-saphira-wordexp-nocmd-nested.patch"
	echo "$nocmd_nested_patch_sha256  $P25" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P25"
	# Arithmetic close + quotes (Sinew 0023): spaced-close blocking,
	# dq-spans in arithmetic, literal '{'. Applied after 0022.
	P26="$RECIPE_DIR/files/0023-saphira-wordexp-arith-close-quotes.patch"
	echo "$arith_close_quotes_patch_sha256  $P26" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P26"
	# fmal subnormal underflow (Sinew 0024): tiny+inexact implies
	# underflow in the TONEAREST denormal tail. Applied after 0023
	# (independent file, order is documentary).
	P27="$RECIPE_DIR/files/0024-saphira-fmal-underflow.patch"
	echo "$fmal_underflow_patch_sha256  $P27" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P27"
	# wordexp ANSI-C quoting context (Sinew 0025): context-sensitive
	# cmdsubst detection inside $'...' spans. Applied after 0024
	# (independent function, order is documentary).
	P28="$RECIPE_DIR/files/0025-saphira-wordexp-ansi-quoting.patch"
	echo "$ansi_quoting_patch_sha256  $P28" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P28"
	# regex backref multibyte resync (Sinew 0026): byte-correct
	# positions in retry advance, pop restore, backref compare and
	# advance, and EOS check. Applied after 0025 (independent file,
	# order is documentary).
	P29="$RECIPE_DIR/files/0026-saphira-regex-backref-multibyte.patch"
	echo "$regex_backref_mb_patch_sha256  $P29" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P29"
	# fnmatch audit residuals (Sinew 0027): chained-range literal
	# hyphen plus PATHNAME-splitter invalid-byte guard. Applied after
	# 0026 (independent file, order is documentary).
	P30="$RECIPE_DIR/files/0027-saphira-fnmatch-audit-residuals.patch"
	echo "$fnmatch_audit_patch_sha256  $P30" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P30"
	# scanf multi-digit positional (Sinew 0028): parse full decimal N
	# before '$' in both vfscanf and vfwscanf. Applied after 0027.
	P31="$RECIPE_DIR/files/0028-saphira-scanf-multidigit-positional.patch"
	echo "$scanf_positional_patch_sha256  $P31" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P31"
	# scanf short-%c input failure (Sinew 0029): EOF before width
	# completes is input failure in vfscanf and vfwscanf. After 0028.
	P32="$RECIPE_DIR/files/0029-saphira-scanf-short-input-fail.patch"
	echo "$scanf_short_input_patch_sha256  $P32" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P32"
	# scanf wide-%c character counting (Sinew 0030): wide %c stops
	# after width complete characters, not bytes. After 0029.
	P33="$RECIPE_DIR/files/0030-saphira-scanf-wide-char-count.patch"
	echo "$scanf_wide_count_patch_sha256  $P33" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P33"
	# swscanf wide-input adapter (Sinew 0031 WN4): locale-independent
	# UTF-8 encoding plus C.UTF-8 stream pin; engine reused untouched.
	# Applied after 0030 (independent file, order is documentary).
	P34="$RECIPE_DIR/files/0031-saphira-swscanf-wide-adapter.patch"
	echo "$swscanf_wide_adapter_patch_sha256  $P34" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P34"
	# floatscan nan sign (Sinew 0032): sign-preserving NaN returns in
	# __floatscan. Applied after 0031 (independent file, order is
	# documentary).
	P35="$RECIPE_DIR/files/0032-saphira-floatscan-nan-sign.patch"
	echo "$nan_sign_patch_sha256  $P35" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P35"
	# wordexp NOCMD close-quote (Sinew 0033): "$(" treated as live
	# command substitution when a dq context may close (or inside
	# arithmetic); validated ((...)) still passes via arith_ok.
	# Applied after 0032 (independent file, order is documentary).
	P36="$RECIPE_DIR/files/0033-saphira-wordexp-nocmd-close-quote.patch"
	echo "$nocmd_close_quote_patch_sha256  $P36" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P36"
	# mallocng huge-overalignment (Sinew 0034): munmap the tail when
	# headroom exceeds INT_MAX, keeping slot metadata exact.
	# Applied after 0033 (independent file, order is documentary).
	P37="$RECIPE_DIR/files/0034-saphira-alloc-huge-align.patch"
	echo "$huge_align_patch_sha256  $P37" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P37"
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

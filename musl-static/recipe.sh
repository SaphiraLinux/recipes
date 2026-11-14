#!/bin/sh
# musl-static 1.2.6_p1-r1 — static-only Saphira musl toolchain.
#
# Derivative of the authoritative /recipes/musl recipe (Sinew lineage).
# It MUST track musl's source, patches, arch assembly and configuration
# exactly. musl is the single source of truth and is never modified by
# this package.
#
# Sharing model (no symlinks, ever):
# - files/ holds proper byte copies of every musl input (ball, sha256
#   sidecar, 0001-0012 + 0014 patches, 0101-0171 upstream series,
#   UPSTREAM-SHA256SUMS). Verified: `diff <(ls ../musl/files)
#   <(ls files)` is empty and `find files -type l | wc -l` is 0.
# - recipe_build starts with a drift guard: every files/* entry is
#   cmp(1)-compared against ../musl/files/<same-name> and the build
#   fails closed on any difference ("refresh from musl").
# - All sha256 pins below are verbatim copies of musl's pins at
#   musl commit 6af7a14d (1.2.6_p1-r6). Editing a patch without
#   refreshing its pin fails the build visibly, same as musl.
# - Refresh procedure: copy changed inputs from /recipes/musl/files/
#   (cp, never ln -s), copy updated pins from /recipes/musl/recipe.sh,
#   update the musl-commit reference below. Never edit a copy in place
#   to diverge from musl.
#
# Tracked musl commit: 6af7a14d (1.2.6_p1-r6).
# Sinew implementation version (matches musl): 0.1.0.
#
# Differences from musl (deliberate, documented):
# - Isolated prefix /opt/saphira/musl-static (headers, static archive,
#   CRT objects, wrappers). Nothing under /lib, /usr or /etc, so this
#   package never collides with musl/musl-dev payload paths and never
#   touches the live libc.
# - Static-only payload: after `make install` the shared objects
#   (libc.so, ld-musl symlink) are pruned. Ships libc.a (static-PIE
#   capable, same AOBJS=LOBJS policy as musl), CRT objects, headers,
#   upstream musl-gcc (prefix-aware) plus the dedicated static wrapper
#   bin/musl-static-gcc (forces -static against the isolated headers
#   and archive).
# - Same configure baseline as musl, relocated under the prefix:
#   syslibdir inside the prefix keeps any loader pathname off /lib.
# - Same static-PIE piecheck as musl (absolute 32-bit relocations fail).
# - No live-seed parity report (different prefix, nothing to compare).
#
# Usage (on the target, after install):
#   musl-static-gcc foo.c -o foo   # static binary, Saphira musl code

pkgname=musl-static
pkgver=1.2.6_p1
_sinew_version=0.1.0
# New package, first release. Tracks musl 1.2.6_p1 source; pkgrel is
# independent of musl's pkgrel (musl is r6, this starts at 1).
pkgrel=11
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='Sinew static toolchain — isolated musl headers + static libc'
license='MIT'
origin=musl-static
repo=saphira
url=https://musl.libc.org/

# Pins below are verbatim copies of /recipes/musl/recipe.sh at 6af7a14d.
musl_ball_sha256=e9db8b70b0cba3db43b27e84ccd8a0c0958b40029a1c36c9f13817b93787b4d6
musl_stack_sha256=e74dcb8dd4aaf6bf9ad1410a3394343bbfbfb34e55007c83fe2b63dccc5767cc
in6_patch_sha256=28ea1e653d0b4e242065714c2018aed67d68ce06dc5cd8526ef735a1a5a06d01
utmp_patch_sha256=e8eab82e03d975af6d0dbd33af878e85dbe5909059c8871248868bd7fc7b11a6
rint_patch_sha256=f5b27c7dac830a02985685337cbca2ddb32ffcbdb7eccf79b0e7a070d17da5c5
strncmp_patch_sha256=be76e9d667157364819089eeedc0824b7bc42e1025f680871bc96bdd0fdd3b3c
memcmp_patch_sha256=8ecdce7e87c156aa47b0d21b2890bbaf0033ccb8a28a3837c7bf090fa8aa0759
memmove_patch_sha256=4ded70ad91844e99c332a16a043ec84b20694daf70b5cb705e601fe55c00a644
floor_patch_sha256=7bbc00ffae9ef528872e0e4caf507574e5b5a00cd558ee03d9e46d09d4f0ad8e
ceil_patch_sha256=0373f2d97238b1a99841b2778a6ee7bb0a6d2350a22fb7dfe436c9ef8ab80501
trunc_patch_sha256=27205918544f6aa6fae2ec1ba4c7c325fa5da2a0173a8c351ccdc46702fe0285
rint_realop_patch_sha256=24b768fb16cb26ca9d032b32e65c35d107b2254cc732293097bc46b11d662147
nearbyint_patch_sha256=d7331d5f7259f85e24915160c78209d95f4d4f26afee4367e840fdb92b68946c
strstr_sse2_patch_sha256=7e1345773f9fe05519d3b09b31f9e89e8e51e9ba703555be66d590a8e382a563
# Sinew clone3 raw primitive (sinew/foundation step 7): new
# src/linux/clone3.c, internal __clone3 only (hidden, no public
# declaration). Drop file + block to remove it entirely.
clone3_patch_sha256=9fd33f5edff7e7af60b4551034fe0748539cb5bf8591a018ce6821956f586542
# Saphira wordexp WRDE_NOCMD hardening (bugs/wordexp-nocmd-bypass.md,
# mirrored from musl; byte-identical file).
wordexp_nocmd_patch_sha256=d56eacb6f49e442de554cc0491c6b67fb55bd86ffec87b1159d4b36b57f27af0
# powf y==1 exact fast path (mirrored from musl).
powf_y1_patch_sha256=af7884a0f21a02561525f5fc8cfa615c04b3a33a424fad6792c253c5f2e6b695
# strptime %z hours-only form (mirrored from musl).
strptime_z_patch_sha256=208f8d3320cc1cbd9d0331ea72dfecf35f9c714c162ddca163bbd7263ef6ba9a
# strptime %s epoch conversion (mirrored from musl).
strptime_s_patch_sha256=8cf061f7e2d31129d1da1a96c8439f5ce61cf64031ec930c028a063672634491
# wordexp WRDE_UNDEF forkless check (mirrored from musl).
undef_check_patch_sha256=995b1eef5f3d5cae736459e9d1e8540cf4353f4a8b2a6d636d625db88e47878e
# wordexp Class-B parameter parser (mirrored from musl).
classb_quotes_patch_sha256=192bb04789b23b81e2fa926ca9a7da265e7ae087491effbe826684a07082cec3
# wordexp NOCMD nested-brace hardening (mirrored from musl).
nocmd_nested_patch_sha256=525a5f0d3eabd4001c30123ff8f24133a6f172a2e14d663d8c10311cb87403be
# wordexp arithmetic close + quotes (mirrored from musl).
arith_close_quotes_patch_sha256=2fe500c65ac48cda52c38f05bfaba48bb770fc25596fb5b4f6d98faaea7051d4
# fmal subnormal underflow (mirrored from musl).
fmal_underflow_patch_sha256=209bdd517e516352c65f6d7c63040995be86f530f67e7e7e36fa7949ce0e3715
# wordexp ANSI-C quoting context (mirrored from musl).
ansi_quoting_patch_sha256=c8f7533a51a3d9916ba8c14364a0a0745608094de2bba46e04394ef71f59b3ab
# regex backref multibyte resync (mirrored from musl).
regex_backref_mb_patch_sha256=bef68736877448ba2202cc3b46ad92584bb4bf0c93bd606e254ec11fd65eca0a
# fnmatch audit residuals (mirrored from musl).
fnmatch_audit_patch_sha256=70f64aecbb2ba04a73eba5bc71719d6d908cf44075fb99c0b2b963d9d7a365f2
# scanf multi-digit positional (mirrored from musl).
scanf_positional_patch_sha256=356df39d26e268374d1c4af25beeb812b94727f2d6b244cacb175270a3a899ba
# scanf short-%c input failure (mirrored from musl).
scanf_short_input_patch_sha256=0dfcae7e6795060a498cb8fc38b015de9f1bea5e077701920c0d364439294338
# scanf wide-%c character counting (mirrored from musl).
scanf_wide_count_patch_sha256=7a04202990fa1926ac5b8620553eed5d9a876fb7ad0bfcda1e57e97fdb3a57fd
# swscanf wide-input adapter (mirrored from musl).
swscanf_wide_adapter_patch_sha256=7a585d183953bb616fe90871b451dd96f03ff23b0b9ac25c336f1f8a9f6e40fb
# floatscan nan sign (mirrored from musl).
nan_sign_patch_sha256=a8ea20789e36555a818ae4fb0092c5b6d156a472a5eb5d6e7f030082de0aab0e
# wordexp NOCMD close-quote (mirrored from musl).
nocmd_close_quote_patch_sha256=c21ddf3b81e5217b439be6465227a6d733e019e930e03a4140110e221f501f31
# mallocng huge-overalignment (mirrored from musl).
huge_align_patch_sha256=7d08bf676ec0791a3185716f31a2ce83008a59cb742c9d7f8022d79415b4f6ff

depends=""
makedepends="
	binutils
	gcc
	make
"

subpackages=""

recipe_build()
{
	# Drift guard: files/ must stay byte-identical to authoritative musl.
	for f in "$RECIPE_DIR"/files/*; do
		b=${f##*/}
		cmp -s "$f" "$RECIPE_DIR/../musl/files/$b" || {
			echo "musl-static: drift: files/$b differs from authoritative ../musl/files/$b; refresh by copying from /recipes/musl (cp, never symlink)" >&2
			return 1
		}
	done
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
	P8="$RECIPE_DIR/files/0004-x86_64-rint-roundsd.patch"
	echo "$rint_patch_sha256  $P8" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P8"
	P9="$RECIPE_DIR/files/0005-x86_64-memmove-sse2-backward.patch"
	echo "$memmove_patch_sha256  $P9" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P9"
	P10="$RECIPE_DIR/files/0006-x86_64-strncmp-sse2.patch"
	echo "$strncmp_patch_sha256  $P10" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P10"
	P11="$RECIPE_DIR/files/0007-x86_64-memcmp-sse2.patch"
	echo "$memcmp_patch_sha256  $P11" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P11"
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
	# Sinew clone3 raw primitive (sinew/foundation step 7): new
	# src/linux/clone3.c only; no existing files touched.
	P18="$RECIPE_DIR/files/0015-sinew-clone3-raw-primitive.patch"
	echo "$clone3_patch_sha256  $P18" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P18"
	# Saphira wordexp WRDE_NOCMD hardening (mirrored from musl).
	P19="$RECIPE_DIR/files/0016-saphira-wordexp-nocmd-scan.patch"
	echo "$wordexp_nocmd_patch_sha256  $P19" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P19"
	# powf y==1 exact fast path (mirrored from musl).
	P20="$RECIPE_DIR/files/0017-saphira-powf-y1-exact.patch"
	echo "$powf_y1_patch_sha256  $P20" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P20"
	# strptime %z hours-only form (mirrored from musl).
	P21="$RECIPE_DIR/files/0018-saphira-strptime-z-hours.patch"
	echo "$strptime_z_patch_sha256  $P21" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P21"
	(cd "$RECIPE_DIR/files" && sha256sum -c UPSTREAM-SHA256SUMS) || return 1
	for up in "$RECIPE_DIR"/files/01[0-9][0-9]-upstream-*.patch; do
		patch -d "$SRC" -Np1 -i "$up"
	done
	# strptime %s epoch conversion (mirrored from musl; applied
	# after upstream to match 0104 context).
	P22="$RECIPE_DIR/files/0019-saphira-strptime-s-epoch.patch"
	echo "$strptime_s_patch_sha256  $P22" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P22"
	# WRDE_UNDEF forkless check (mirrored from musl; applied
	# after upstream to match 0138/0153/0154 context).
	P23="$RECIPE_DIR/files/0020-saphira-wordexp-undef-forkless.patch"
	echo "$undef_check_patch_sha256  $P23" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P23"
	# Class-B parameter parser (mirrored from musl; applied after 0020).
	P24="$RECIPE_DIR/files/0021-saphira-wordexp-classb-quotes.patch"
	echo "$classb_quotes_patch_sha256  $P24" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P24"
	# NOCMD nested-brace hardening (mirrored from musl).
	P25="$RECIPE_DIR/files/0022-saphira-wordexp-nocmd-nested.patch"
	echo "$nocmd_nested_patch_sha256  $P25" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P25"
	# Arithmetic close + quotes (mirrored from musl; applied after 0022).
	P26="$RECIPE_DIR/files/0023-saphira-wordexp-arith-close-quotes.patch"
	echo "$arith_close_quotes_patch_sha256  $P26" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P26"
	# fmal subnormal underflow (mirrored from musl; applied after 0023).
	P27="$RECIPE_DIR/files/0024-saphira-fmal-underflow.patch"
	echo "$fmal_underflow_patch_sha256  $P27" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P27"
	# wordexp ANSI-C quoting context (mirrored from musl; applied after 0024).
	P28="$RECIPE_DIR/files/0025-saphira-wordexp-ansi-quoting.patch"
	echo "$ansi_quoting_patch_sha256  $P28" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P28"
	# regex backref multibyte resync (mirrored from musl; applied after 0025).
	P29="$RECIPE_DIR/files/0026-saphira-regex-backref-multibyte.patch"
	echo "$regex_backref_mb_patch_sha256  $P29" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P29"
	# fnmatch audit residuals (mirrored from musl; applied after 0026).
	P30="$RECIPE_DIR/files/0027-saphira-fnmatch-audit-residuals.patch"
	echo "$fnmatch_audit_patch_sha256  $P30" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P30"
	# scanf multi-digit positional (mirrored from musl; applied after 0027).
	P31="$RECIPE_DIR/files/0028-saphira-scanf-multidigit-positional.patch"
	echo "$scanf_positional_patch_sha256  $P31" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P31"
	# scanf short-%c input failure (mirrored from musl; applied after 0028).
	P32="$RECIPE_DIR/files/0029-saphira-scanf-short-input-fail.patch"
	echo "$scanf_short_input_patch_sha256  $P32" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P32"
	# scanf wide-%c character counting (mirrored from musl; applied after 0029).
	P33="$RECIPE_DIR/files/0030-saphira-scanf-wide-char-count.patch"
	echo "$scanf_wide_count_patch_sha256  $P33" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P33"
	# swscanf wide-input adapter (mirrored from musl; applied after 0030).
	P34="$RECIPE_DIR/files/0031-saphira-swscanf-wide-adapter.patch"
	echo "$swscanf_wide_adapter_patch_sha256  $P34" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P34"
	# floatscan nan sign (mirrored from musl; applied after 0031).
	P35="$RECIPE_DIR/files/0032-saphira-floatscan-nan-sign.patch"
	echo "$nan_sign_patch_sha256  $P35" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P35"
	# wordexp NOCMD close-quote (mirrored from musl; applied after 0032).
	P36="$RECIPE_DIR/files/0033-saphira-wordexp-nocmd-close-quote.patch"
	echo "$nocmd_close_quote_patch_sha256  $P36" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P36"
	# mallocng huge-overalignment (mirrored from musl; applied after 0033).
	P37="$RECIPE_DIR/files/0034-saphira-alloc-huge-align.patch"
	echo "$huge_align_patch_sha256  $P37" | sha256sum -c -
	patch -d "$SRC" -Np1 -i "$P37"
	cd "$SRC"
	# Isolated prefix: everything stays under /opt/saphira/musl-static.
	./configure --prefix=/opt/saphira/musl-static --sysconfdir=/opt/saphira/musl-static/etc --syslibdir=/opt/saphira/musl-static/lib --localstatedir=/opt/saphira/musl-static/var
	# Same static-PIE policy as musl.
	printf '%s\n' \
		'# Saphira policy: libc.a must be static-PIE capable.' \
		'AOBJS = $(LOBJS)' >> config.mak
	make -j${JOBS:-$(nproc)}

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
}

recipe_install()
{
	make -C "$SRC" DESTDIR="$PKGDEST" install
	PREFIX="$PKGDEST/opt/saphira/musl-static"
	# Static-only: prune the shared objects. Keep libc.a, CRT objects,
	# headers and compiler tools.
	rm -f "$PREFIX"/lib/libc.so "$PREFIX"/lib/ld-musl-*.so.1
	# Dedicated static-linking wrapper (generated here so files/ stays
	# an exact copy of musl's inputs). Upstream's own musl-gcc tool is
	# intentionally absent: configure empties ALL_TOOLS on musl hosts
	# ("toolchain wrapper to build... none"), so bin/ needs creating.
	install -d -m 0755 "$PREFIX/bin"
	cat > "$PREFIX/bin/musl-static-gcc" <<'EOF'
#!/bin/sh
# musl-static-gcc: static-only wrapper for /opt/saphira/musl-static.
# Forces -static against the isolated headers and archive so static
# builds exercise the same Saphira musl code as the dynamic libc.
prefix=/opt/saphira/musl-static
exec ${CC:-gcc} -static -nostdinc -B"$prefix/lib" -isystem "$prefix/include" -L"$prefix/lib" "$@"
EOF
	chmod 0755 "$PREFIX/bin/musl-static-gcc"
}

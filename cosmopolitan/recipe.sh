#!/bin/sh

# Cosmopolitan libc + cosmocc toolchain, bootstrapped from Saphira source.
#
# One C source compiles to a single dual-architecture (x86_64 + AArch64)
# multi-OS APE executable. No precompiled toolchain, no bootstrap binary
# download, no submodules, no archives stored in Git: every byte is pinned
# by URL + SHA-256 and arrives through the Saphira source cache.
#
# Pins (provenance, hashes and the licensing split live in
# files/PROVENANCE.md; loader policy in files/LOADER.md; port audit in
# files/PATCHES.md):
#   monorepo  commit aefad27c09ffda64c6ac64bd69f758e9f9c7b91d (2026-10-20)
#   GCC       16.2.0 release tarball (ftp.gnu.org; Saphira's own pin)
#   binutils  2.42 release tarball (ftp.gnu.org)
#   portcosmo files/portcosmo-16.2.patch: the portcosmo-14.1 fork
#   (ahgamut/gcc branch portcosmo-14.1, diff cd0059a19763...58ccca83,
#   34 files) adapted to GCC 16.2.0 — same 34-file set, 28 hunks verbatim,
#   6 re-anchored, final patch verified perfectly clean against pristine
#   16.2.0 before this recipe was written.
#
# Bootstrap design (why each upstream binary dependency is unnecessary):
#   download-cosmocc.sh  never executed: the recipe pre-creates
#     $SRC/.cosmocc/3.9.2/bin as a symlink farm to the source-built
#     compilers, and the script exits 0 on an existing directory
#     (upstream's own idempotency, not a hack).
#   SHELL=cocmd (APE)    -> make override SHELL=/bin/sh.
#   COMPILE=compile.ape  -> generated passthrough shim (its -A/-w/-t/-V/-M/
#     -P/-Q flags are audit/sandbox labels; sandboxing is the outer
#     Bubblewrap namespace). Logged at build time; revisited if logs demand.
#   TLSCC=tlscc (APE)    -> generated exec-"$@" shim (its documented effect,
#     -mno-red-zone -mno-tls-direct-seg-refs, already travels in
#     CFLAGS_X86_64; a non-empty TLSCC preserves the DEFAULT_COPTS branch).
#   AR/CP/... (byte-mechanical) -> symlinks to system tools in hostbin/
#     (ar format is architecture-independent, covering both arch sets).
#   fixupobj/package/elf2pe (link the libc itself, so musl builds are
#     impossible; fixupobj is load-bearing, so skipping is unsound) ->
#     two-pass bootstrap in stage 3c: every object with default flags
#     minus ftrace (ENABLE_FTRACE=), manual LD link of package.dbg
#     (x86_64 ET_REL without patchable entries or ifuncs needs no fixup —
#     audited), then real .pkgs and fixupobj/elf2pe .dbgs. Pass 2 builds
#     the full tree with those tools. Nothing forked, nothing
#     reimplemented: every byte compiled comes from upstream sources.
#
# Naming verdict (binding): upstream names are kept byte-identical and
# RELOCATED under /usr/lib/cosmopolitan/, never renamed. Per-OS compilers
# (x86_64-freebsd-*, x86_64-windows-*, ...) are rejected by design: one
# x86_64-linux-cosmo-gcc already emits multi-OS output via cosmopolitan.a
# + apelink, and invented vendor fields would fork the Saphira
# *-akadata-linux-musl identity while breaking superconfigure/autoconf
# expectations (CC=x86_64-unknown-cosmo-cc). Overlap with gcc/clang is
# prevented structurally (target-prefixed names only, asserted below),
# mirroring the cross-toolchain recipe, never by renaming upstream.
#
# Scope of this revision: default MODE= runtime only (no tiny/sysv/dbg/
# optlinux/tinylinux libraries), GCC path only (no Clang rebuild), C +
# C++ drivers with libstdc++ off (Cosmopolitan uses LLVM libcxx from
# third_party/). Follow-ups are documented in files/PROVENANCE.md.

pkgname=cosmopolitan
pkgver=2026.10.20
pkgrel=1
disabled=yes
disabled_reason='parked on operator direction: dual-arch APE port paused, builder must not queue it; re-enable to resume'
pkgarch=${SAPHIRA_ARCH:-x86_64}
case "$pkgarch" in
x86_64) ;;
*)
	echo "ERROR: cosmopolitan builds on a Saphira x86_64 host only (crosses to AArch64 from there)" >&2
	return 1
	;;
esac
pkgdesc='Cosmopolitan libc and cosmocc toolchain (build-once run-anywhere APE executables)'
license='ISC AND GPL-3.0-or-later'
origin=cosmopolitan
repo=saphira
url=https://github.com/jart/cosmopolitan
# Source policy (operator direction): NO archives in files/, NO vendor=/
# pair — the vendored-sources gate would demand a files/ copy of any
# declared pair. All sources arrive exclusively through the in-recipe
# source-cache path below (cache hit, else verified download), pinned by
# URL + SHA-256; any mismatch fails closed. This is the multi-source
# pattern (cross-toolchain precedent for its extras), extended to all
# inputs because this package is inherently multi-source. The portcosmo
# patch itself is a text patch in files/ (it has no upstream URL: it is
# Saphira's adaptation of the portcosmo-14.1 fork to GCC 16.2 — see
# files/PATCHES.md for the hunk-by-hunk audit).
COSMO_COMMIT=aefad27c09ffda64c6ac64bd69f758e9f9c7b91d
COSMO_URL=https://github.com/jart/cosmopolitan/archive/aefad27c09ffda64c6ac64bd69f758e9f9c7b91d.tar.gz
COSMO_SHA256=2ad113d1735280479183fee0a6b65159ca1999005a69b6d06cd5ec945e3fa32c
# GCC 16.2.0 (development branch: Master stays on the 14.1 baseline until
# this passes). SHA-256 is Saphira's own pin from the gcc recipe — the
# downloaded bytes verified identical before this recipe was written.
GCC_VER=16.2.0
GCC_URL=https://ftp.gnu.org/gnu/gcc/gcc-16.2.0/gcc-16.2.0.tar.xz
GCC_SHA256=e6738e29597f733270731aa90600f37ffdc045079dfc27ec7e8192cc81085c3e
BINUTILS_VER=2.42
BINUTILS_URL=https://ftp.gnu.org/gnu/binutils/binutils-2.42.tar.xz
BINUTILS_SHA256=f6e4d41fd5fc778b06b7891457b3620da5ecea1006c6a4a41ae998109f85a800

# The compilers link GMP/MPFR/MPC/zlib dynamically: like the
# cross-toolchain recipe, the runtime closure carries them so the
# installed toolchain runs on minimal systems.
depends="
	gcc-libs
	gmp
	mpfr
	mpc
	zlib
	zstd
"

makedepends="
	binutils
	bison
	curl
	flex
	gawk
	gcc
	gmp-dev
	isl-dev
	m4
	make
	mpc-dev
	mpfr-dev
	perl
	python3
	zlib-dev
	zstd-dev
"

COSMOPREFIX=/usr/lib/cosmopolitan

# fetch_verified <url> <sha256> <dest>: shared cache hit (verified), else
# curl with retries (verified, best-effort cache populate). Fail-closed on
# any mismatch. (cross-toolchain idiom.)
fetch_verified()
{
	local url=$1 sha=$2 dest=$3
	local base cache ctmp
	base=${url##*/}
	cache=${SAPHIRA_SOURCE_CACHE-}
	if [ -n "$cache" ] && [ -f "$cache/$sha" ]; then
		echo "$sha  $cache/$sha" | sha256sum -c - || return 1
		cp -- "$cache/$sha" "$dest" || return 1
		return 0
	fi
	curl -fL --retry 3 --output "$dest" "$url" || return 1
	echo "$sha  $dest" | sha256sum -c - || { rm -f -- "$dest"; return 1; }
	if [ -n "$cache" ]; then
		ctmp=$cache/.tmp.$$.download
		cp -- "$dest" "$ctmp" 2>/dev/null && mv -- "$ctmp" "$cache/$sha" 2>/dev/null || true
	fi
}

# unpack_verified <url> <sha256> <destdir>: fetch then extract a single
# top-level tree, stripped, into destdir.
unpack_verified()
{
	local url=$1 sha=$2 destdir=$3
	local dl
	mkdir -p "$destdir" || return 1
	dl=$destdir/.dl-$(basename "$url")
	fetch_verified "$url" "$sha" "$dl" || return 1
	tar --no-same-owner -C "$destdir" --strip-components=1 -xf "$dl" || return 1
	rm -f -- "$dl"
}

recipe_build()
{
	HOST_TRIPLET=${SAPHIRA_HOST_TRIPLET:-$(gcc -dumpmachine)}
	case "$HOST_TRIPLET" in
	x86_64-akadata-linux-musl) ;;
	*)
		echo "ERROR: unsupported build host: $HOST_TRIPLET" >&2
		return 1
		;;
	esac
	PKGVER="Saphira cosmopolitan $pkgver (gcc $GCC_VER + portcosmo-16.2 binutils $BINUTILS_VER)"
	# NOTE: $PKGVER must not contain a comma: bfd's version.h ->
	# bfdver.h rule substitutes @bfd_version_package@ with sed using ','
	# as delimiter (build row 6045 evidence: a comma silently emptied
	# bfdver.h, hence BFD_VERSION_STRING undeclared). '&' and '\' are
	# likewise forbidden in the replacement.

	# makeinfo is absent from build roots and this package ships no info
	# pages (share/ is pruned at install). Automake doc rules carry an
	# explicit MAKEINFO file assignment, which beats the environment, so
	# the stub MUST ride each binutils/GCC make command line (build 6044
	# evidence: exported MAKEINFO=true still died at bfd/doc/bfd.info
	# Error 127). Recipe-local only; the system texinfo package and all
	# other recipes are untouched.
	MAKEINFO_STUB="MAKEINFO=true"

	DEPSRC=$BUILDDIR/extra-sources
	HOSTBIN=$BUILDDIR/hostbin
	mkdir -p "$DEPSRC" "$HOSTBIN" || return 1
	# The monorepo itself arrives through the same cache path (no
	# builder pre-extract: this recipe declares no vendor= pair, so
	# $SRC starts empty and is populated here, deterministically).
	COSMODL=$DEPSRC/cosmo.tar.gz
	fetch_verified "$COSMO_URL" "$COSMO_SHA256" "$COSMODL" || return 1
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$COSMODL" || return 1
	rm -f -- "$COSMODL"
	# Refuse anything but the pinned tree.
	test -f "$SRC/Makefile" || { echo "ERROR: \$SRC is not the cosmopolitan tree" >&2; return 1; }
	test -f "$SRC/build/download-cosmocc.sh" || { echo "ERROR: unexpected cosmopolitan tree layout" >&2; return 1; }
	test -d "$SRC/tool/cosmocc/bin" || { echo "ERROR: tool/cosmocc/bin missing" >&2; return 1; }
	if [ -d "$SRC/.cosmocc" ]; then
		echo "ERROR: \$SRC/.cosmocc already exists; refusing to build over a bootstrap residue" >&2
		return 1
	fi

	DEPSRC=$BUILDDIR/extra-sources
	HOSTBIN=$BUILDDIR/hostbin
	mkdir -p "$DEPSRC" "$HOSTBIN" || return 1
	unpack_verified "$GCC_URL" "$GCC_SHA256" "$DEPSRC/gcc" || return 1
	unpack_verified "$BINUTILS_URL" "$BINUTILS_SHA256" "$DEPSRC/binutils" || return 1

	# Stage 0: portcosmo-16.2 onto pristine GCC 16.2.0 (dry-run first,
	# fail-closed). The patch lives in files/ (Saphira's adaptation —
	# no upstream URL exists for it); audit in files/PATCHES.md.
	patch -d "$DEPSRC/gcc" -Np1 --dry-run \
		-i "$RECIPE_DIR/files/portcosmo-16.2.patch" \
		|| { echo "ERROR: portcosmo-16.2 patch does not apply to gcc-$GCC_VER" >&2; return 1; }
	patch -d "$DEPSRC/gcc" -Np1 \
		-i "$RECIPE_DIR/files/portcosmo-16.2.patch" \
		|| return 1
	echo "portcosmo-16.2: applied to gcc-$GCC_VER"

	# Stage 0b: binutils-side cosmo acceptance (machine-generated patch in
	# files/; GCC's hunk does not fit binutils' newer config.sub).
	patch -d "$DEPSRC/binutils" -Np1 --dry-run \
		-i "$RECIPE_DIR/files/0001-config-sub-cosmo.patch" \
		|| { echo "ERROR: config.sub patch does not apply to binutils-$BINUTILS_VER" >&2; return 1; }
	patch -d "$DEPSRC/binutils" -Np1 \
		-i "$RECIPE_DIR/files/0001-config-sub-cosmo.patch" \
		|| return 1
	"$DEPSRC/binutils/config.sub" x86_64-linux-cosmo >/dev/null \
		|| { echo "ERROR: patched config.sub still rejects x86_64-linux-cosmo" >&2; return 1; }
	"$DEPSRC/binutils/config.sub" aarch64-linux-cosmo >/dev/null \
		|| { echo "ERROR: patched config.sub still rejects aarch64-linux-cosmo" >&2; return 1; }
	echo "config.sub: accepts both cosmo triplets"

	# Stage 1: bootstrap seed — shims and system symlinks only. The
	# monorepo's build tools link the Cosmopolitan libc itself, so they
	# cannot be compiled natively against musl; fixupobj is load-bearing
	# (TLS rewrites, APE flags), so it cannot be skipped either. Pass 1
	# (stage 3c, once the compilers exist) therefore builds every object
	# with stock default-mode flags minus ftrace and links the three
	# load-bearing tools manually; pass 2 (stage 4) is the normal full
	# build using them. x86_64 ET_REL objects without patchable entries
	# or ifuncs need no fixup (audited: no STT_GNU_IFUNC producers in any
	# compiled source; ENABLE_FTRACE= suppresses patchable entries). No
	# upstream source is forked or reimplemented anywhere in this chain.
	# compile.ape passthrough shim: strips the audit/sandbox labels
	# (-A* -w* -t* -V* -M* -P* -Q* -C* -L* as LEADING tokens only) and
	# execs the real command. Sandboxing stays with the outer namespace.
	cat > "$HOSTBIN/compile.ape" <<'SHIMEOF'
#!/bin/sh
# Generated by the cosmopolitan recipe (see header): passthrough for
# upstream compile.ape. Drops leading audit/sandbox label flags, execs
# the remainder unchanged. Any leading-token strip is safe because every
# real command the build issues starts with a program path.
while [ $# -gt 0 ]; do
	case "$1" in
	-A*|-w*|-t*|-V*|-M*|-P*|-Q*|-C*|-L*) shift ;;
	*) break ;;
	esac
done
if [ $# -eq 0 ]; then
	echo "compile-shim: nothing to execute" >&2
	exit 1
fi
exec "$@"
SHIMEOF
	chmod 0755 "$HOSTBIN/compile.ape"
	echo "hosttools: compile.ape shim installed (sandboxing remains with the build namespace)"
	# tlscc shim: plain passthrough; the -mno-red-zone /
	# -mno-tls-direct-seg-refs effect travels in CFLAGS_X86_64, and a
	# non-empty TLSCC preserves the DEFAULT_COPTS branch.
	cat > "$HOSTBIN/tlscc" <<'SHIMEOF'
#!/bin/sh
# Generated by the cosmopolitan recipe (see header): passthrough for
# upstream build/bootstrap/tlscc (an APE binary we do not execute).
exec "$@"
SHIMEOF
	chmod 0755 "$HOSTBIN/tlscc"
	# Byte-mechanical BOOTSTRAP names resolve to system tools (ar format
	# is architecture-independent, so host ar archives both arch sets).
	for t in ar cp rm gzip echo chmod touch mkdir; do
		p=$(command -v "$t") || { echo "ERROR: system tool missing: $t" >&2; return 1; }
		ln -s "$p" "$HOSTBIN/$t.ape" || return 1
	done

	# Stage 2: binutils for both cosmo targets into the final prefix.
	# --disable-gprofng (documented omission): 2.42's gprofng libcollector
	# uses unprototyped function declarations, which are hard errors under
	# the Saphira GCC 16 host (C23 defaults; fixed upstream only in later
	# binutils — native 2.46.1 builds clean). Even if it compiled, a host
	# profiling runtime is meaningless in a freestanding cosmo cross
	# toolchain that ships no runtime. Native binutils keeps gprofng.
	export PATH="$PKGDEST$COSMOPREFIX/bin:$PATH"
	for target in x86_64-linux-cosmo aarch64-linux-cosmo; do
		mkdir -p "$BUILDDIR/binutils-$target" || return 1
		cd "$BUILDDIR/binutils-$target" || return 1
		"$DEPSRC/binutils/configure" \
			--prefix=$COSMOPREFIX \
			--sysconfdir=/etc \
			--localstatedir=/var \
			--build=$HOST_TRIPLET --host=$HOST_TRIPLET --target=$target \
			--disable-multilib --disable-nls --disable-werror \
			--disable-gdb --disable-sim \
			--disable-gprofng \
			--with-system-zlib \
			--with-pkgversion="$PKGVER" \
			|| return 1
		make $MAKEINFO_STUB -j${JOBS:-$(nproc)} || return 1
		make $MAKEINFO_STUB DESTDIR="$PKGDEST" install || return 1
	done
	rm -f "$PKGDEST$COSMOPREFIX"/lib/*.la
	rm -rf "$PKGDEST$COSMOPREFIX/lib/bfd-plugins"
	echo "binutils: both cosmo targets installed"

	# Stage 3: portcosmo GCC for both cosmo targets. Freestanding target
	# libraries only (libgcc); C++ driver kept, libstdc++ off (Cosmopolitan
	# uses LLVM libcxx, built by the monorepo in stage 4).
	# Saphira baseline (operator min-spec, mirrors the gcc recipe):
	# x86_64 output requires x86-64-v3, AArch64 output armv8-a, both tuned
	# generic. Resulting APE binaries do NOT run on older CPUs (pre-2013
	# x86-64); see files/PROVENANCE.md. The pending branch-cost patch
	# targets exactly this generic tune (verified separately).
	for target in x86_64-linux-cosmo aarch64-linux-cosmo; do
		case "$target" in
		x86_64-*) GCC_ARCH=x86-64-v3 ;;
		aarch64-*) GCC_ARCH=armv8-a ;;
		esac
		mkdir -p "$BUILDDIR/gcc-$target" || return 1
		cd "$BUILDDIR/gcc-$target" || return 1
		"$DEPSRC/gcc/configure" \
			--prefix=$COSMOPREFIX \
			--sysconfdir=/etc \
			--localstatedir=/var \
			--build=$HOST_TRIPLET --host=$HOST_TRIPLET --target=$target \
			--with-arch="$GCC_ARCH" \
			--with-tune=generic \
			--enable-languages=c,c++ \
			--without-headers --with-newlib \
			--disable-shared --disable-threads \
			--disable-libatomic --disable-libgomp --disable-libquadmath \
			--disable-libstdc++-v3 \
			--disable-libcc1 --disable-libsanitizer --disable-libssp \
			--disable-libvtv --disable-libitm \
			--disable-bootstrap --disable-multilib --disable-nls \
			--disable-fixincludes \
			--disable-werror \
			--with-gmp=/usr --with-mpfr=/usr --with-mpc=/usr \
			--with-system-zlib \
			--with-pkgversion="$PKGVER" \
			|| return 1
		make $MAKEINFO_STUB -j${JOBS:-$(nproc)} INHIBIT_LIBC_CFLAGS=-Dinhibit_libc all-gcc all-target-libgcc \
			|| { echo "ERROR: gcc build failed for $target (genuine blocker evidence above)" >&2; return 1; }
		make $MAKEINFO_STUB DESTDIR="$PKGDEST" install-gcc install-target-libgcc \
			|| return 1
	done
	rm -f "$PKGDEST$COSMOPREFIX"/lib/*.la
	echo "gcc: both cosmo targets installed"

	# Stage 3b: COSMOCC farm so the monorepo's own download step no-ops
	# (download-cosmocc.sh exits 0 when its output dir exists; it is never
	# executed beyond that existence check, and no zip is fetched).
	FARM=$SRC/.cosmocc/3.9.2/bin
	mkdir -p "$FARM" || return 1
	for target in x86_64-linux-cosmo aarch64-linux-cosmo; do
		for tool in as gcc g++ c++filt ld ld.bfd nm strip objcopy objdump addr2line ar ranlib; do
			test -x "$PKGDEST$COSMOPREFIX/bin/$target-$tool" \
				|| { echo "ERROR: farm source missing: $target-$tool" >&2; return 1; }
			ln -s "$PKGDEST$COSMOPREFIX/bin/$target-$tool" "$FARM/$target-$tool" \
				|| return 1
		done
	done
	ln -sfn 3.9.2 "$SRC/.cosmocc/current" || return 1
	echo "farm: .cosmocc/3.9.2 populated from source-built compilers"

	# Stage 3c, pass 1: bootstrap the three load-bearing build tools.
	# -k: PKG/archive/link steps fail (no package.ape yet); every
	# compilable object still completes. The trailing `|| true` is NOT a
	# swallowed failure: the sentinel asserts and the manual link below
	# fail closed with precise evidence when objects are missing.
	P1=$BUILDDIR/pass1
	mkdir -p "$P1" || return 1
	P1MAKE="SHELL=/bin/sh BOOTSTRAP=$HOSTBIN MKDEPS=true ELF2PE=true TLSCC=$HOSTBIN/tlscc"
	make -C "$SRC" -k -j${JOBS:-$(nproc)} -O V=1 $P1MAKE \
		ENABLE_FTRACE= FIXUPOBJ=true PKG=false \
		o/tool/build/package.dbg || true
	for f in tool/build/package.o libc/crt/crt.o \
		 ape/ape-no-modify-self.o ape/ape.lds; do
		test -f "$SRC/o/$f" \
			|| { echo "ERROR: pass-1 object missing: o/$f (genuine blocker evidence in the make log above)" >&2; return 1; }
	done
	echo "pass1: objects complete ($(find "$SRC/o" -name '*.o' | wc -l) objects)"
	find "$SRC/o" -name '*.o' | sort > "$P1/objs.txt" || return 1
	"$HOSTBIN/ar.ape" rcsD "$P1/bootstrap.a" @"$P1/objs.txt" || return 1
	# Manual link of package.dbg, mirroring the o/tool/build/%.dbg rule
	# (LD with LINK.flags from build/definitions.mk, CRT first, -T
	# ape.lds, objects + archive; no fixup — vacuous here by the audit
	# cited in stage 1).
	"$FARM/x86_64-linux-cosmo-ld" \
		-static -nostdlib -znorelro --gc-sections \
		-z noexecstack --build-id=none --no-dynamic-linker \
		-zmax-page-size=0x4000 -zcommon-page-size=0x1000 \
		-T "$SRC/o/ape/ape.lds" \
		"$SRC/o/libc/crt/crt.o" "$SRC/o/tool/build/package.o" \
		"$SRC/o/ape/ape-no-modify-self.o" \
		"$P1/bootstrap.a" -o "$P1/package.dbg" \
		|| { echo "ERROR: manual link of pass-1 package.dbg failed (undefined refs above name the missing surface)" >&2; return 1; }
	test -x "$P1/package.dbg" || { echo "ERROR: pass-1 package.dbg not executable" >&2; return 1; }
	readelf -h "$P1/package.dbg" | grep -q 'Machine:.*X86-64' \
		|| { echo "ERROR: pass-1 package.dbg is not an X86-64 ELF" >&2; return 1; }
	echo "pass1: package.dbg linked ($(ls -l "$P1/package.dbg"))"
	# Real .pkgs, then fixupobj + elf2pe, using the pass-1 package. The
	# .dbg links still skip fixup (FIXUPOBJ=true — same vacuity argument);
	# these are build-host x86_64 ELFs and their proving run is pass 2.
	make -C "$SRC" -j${JOBS:-$(nproc)} -O V=1 $P1MAKE \
		ENABLE_FTRACE= FIXUPOBJ=true PKG=$P1/package.dbg \
		o/tool/build/build.pkg || return 1
	make -C "$SRC" -j${JOBS:-$(nproc)} -O V=1 $P1MAKE \
		ENABLE_FTRACE= FIXUPOBJ=true PKG=$P1/package.dbg \
		o/tool/build/fixupobj.dbg o/tool/build/elf2pe.dbg || return 1
	for t in fixupobj elf2pe; do
		test -f "$SRC/o/tool/build/$t.dbg" \
			|| { echo "ERROR: pass-1 tool missing: o/tool/build/$t.dbg" >&2; return 1; }
		cp -- "$SRC/o/tool/build/$t.dbg" "$P1/$t.dbg" || return 1
	done
	"$P1/fixupobj.dbg" "$(cp -- "$SRC/o/libc/crt/crt.o" "$P1/probe.o" && echo "$P1/probe.o")" \
		|| { echo "ERROR: pass-1 fixupobj.dbg cannot process an object (genuine blocker)" >&2; return 1; }
	echo "pass1: fixupobj + elf2pe bootstrapped and fixupobj proven on an object"
	# Pass-1 objects lack ftrace instrumentation; pass 2 rebuilds the
	# whole tree (pass-1 tools are saved above).
	rm -rf "$SRC/o" || return 1

	# Stage 4, pass 2: monorepo `make toolchain`, x86_64 then AArch64,
	# using the pass-1 tools (FIXUPOBJ/ELF2PE/PKG). check/test targets are
	# never invoked, so no built binary runs except the acceptance smoke
	# tools in stage 6.
	COSMOMAKE="SHELL=/bin/sh BOOTSTRAP=$HOSTBIN MKDEPS=$HOSTBIN/mkdeps ELF2PE=$P1/elf2pe.dbg TLSCC=$HOSTBIN/tlscc FIXUPOBJ=$P1/fixupobj.dbg PKG=$P1/package.dbg"
	make -C "$SRC" -j${JOBS:-$(nproc)} -O V=1 $COSMOMAKE toolchain \
		|| { echo "ERROR: monorepo toolchain build failed for x86_64 (genuine blocker evidence above)" >&2; return 1; }
	for f in ape/ape.lds libc/crt/crt.o libc/crt/crtfastmath.o \
		 ape/ape.elf ape/ape.o cosmopolitan.a third_party/libcxx/libcxx.a \
		 tool/build/apelink tool/build/fixupobj tool/build/zipcopy \
		 tool/build/pecheck tool/build/mktemper; do
		test -f "$SRC/o/$f" \
			|| { echo "ERROR: expected build artifact missing: o/$f" >&2; return 1; }
	done
	echo "monorepo: x86_64 toolchain artifacts present"
	# mkdeps is outside the toolchain closure but is documented user
	# tooling; build it explicitly with the same variables and ship it.
	make -C "$SRC" -j${JOBS:-$(nproc)} -O V=1 $COSMOMAKE o/tool/build/mkdeps.dbg \
		|| { echo "ERROR: mkdeps build failed" >&2; return 1; }
	make -C "$SRC" -j${JOBS:-$(nproc)} -O V=1 m=aarch64 $COSMOMAKE toolchain \
		|| { echo "ERROR: monorepo toolchain build failed for aarch64 (genuine blocker evidence above)" >&2; return 1; }
	for f in ape/ape.elf libc/crt/crt.o libc/crt/crtfastmath.o \
		 cosmopolitan.a third_party/libcxx/libcxx.a; do
		test -f "$SRC/o/aarch64/$f" \
			|| { echo "ERROR: expected aarch64 artifact missing: o/aarch64/$f" >&2; return 1; }
	done
	echo "monorepo: aarch64 toolchain artifacts present"

	# Stage 5: install the runtime into the toolchain layout the upstream
	# wrappers expect ($BIN/../<target>/lib), renaming cosmopolitan.a to
	# the -lcosmo name. Wrappers ship verbatim (plain shell in git).
	XLIB=$PKGDEST$COSMOPREFIX/x86_64-linux-cosmo/lib
	ALIB=$PKGDEST$COSMOPREFIX/aarch64-linux-cosmo/lib
	PBIN=$PKGDEST$COSMOPREFIX/bin
	mkdir -p "$XLIB" "$ALIB" "$PBIN" || return 1
	cp -- "$SRC/o/ape/ape.o" "$SRC/o/libc/crt/crt.o" "$SRC/o/libc/crt/crtfastmath.o" "$XLIB/" || return 1
	cp -- "$SRC/o/cosmopolitan.a" "$XLIB/libcosmo.a" || return 1
	cp -- "$SRC/o/third_party/libcxx/libcxx.a" "$XLIB/" || return 1
	cp -- "$SRC/o/ape/ape.lds" "$XLIB/" || return 1
	cp -- "$SRC/o/aarch64/libc/crt/crt.o" "$SRC/o/aarch64/libc/crt/crtfastmath.o" "$ALIB/" || return 1
	cp -- "$SRC/o/aarch64/cosmopolitan.a" "$ALIB/libcosmo.a" || return 1
	cp -- "$SRC/o/aarch64/third_party/libcxx/libcxx.a" "$ALIB/" || return 1
	cp -- "$SRC/o/aarch64/ape/aarch64.lds" "$ALIB/" || return 1
	# Loaders + Apple Silicon loader source (payload files only; the
	# package never activates them — see files/LOADER.md).
	cp -- "$SRC/o/ape/ape.elf" "$PBIN/ape-x86_64.elf" || return 1
	cp -- "$SRC/o/aarch64/ape/ape.elf" "$PBIN/ape-aarch64.elf" || return 1
	test -f "$SRC/ape/ape-m1.c" \
		|| { echo "ERROR: ape/ape-m1.c missing (genuine blocker: fat binaries need it via apelink -M)" >&2; return 1; }
	cp -- "$SRC/ape/ape-m1.c" "$PBIN/" || return 1
	if [ -f "$SRC/o/ape/ape.macho" ]; then
		cp -- "$SRC/o/ape/ape.macho" "$PBIN/ape-x86_64.macho" || return 1
	else
		echo "note: o/ape/ape.macho not in toolchain closure; skipping (documented)"
	fi
	# Self-hosted build tools (proof the new toolchain builds its own
	# tooling, including mkdeps built explicitly above).
	for t in apelink fixupobj zipcopy pecheck mktemper; do
		test -f "$SRC/o/tool/build/$t" \
			|| { echo "ERROR: self-hosted tool missing: o/tool/build/$t" >&2; return 1; }
		cp -- "$SRC/o/tool/build/$t" "$PBIN/" || return 1
	done
	test -f "$SRC/o/tool/build/mkdeps.dbg" \
		|| { echo "ERROR: self-hosted mkdeps missing" >&2; return 1; }
	cp -- "$SRC/o/tool/build/mkdeps.dbg" "$PBIN/mkdeps" || return 1
	cp -- "$HOSTBIN/tlscc" "$PBIN/tlscc" || return 1
	# Upstream wrapper scripts, verbatim (asserted shell text below).
	for w in cosmocc cosmoc++ cosmoar x86_64-unknown-cosmo-cc x86_64-unknown-cosmo-c++ aarch64-unknown-cosmo-cc aarch64-unknown-cosmo-c++; do
		test -f "$SRC/tool/cosmocc/bin/$w" \
			|| { echo "ERROR: wrapper missing: tool/cosmocc/bin/$w" >&2; return 1; }
		head -1 "$SRC/tool/cosmocc/bin/$w" | grep -q '^#!/bin/sh' \
			|| { echo "ERROR: wrapper is not a shell script (refusing binary): $w" >&2; return 1; }
		cp -a -- "$SRC/tool/cosmocc/bin/$w" "$PBIN/" || return 1
	done
	chmod 0755 "$PBIN"/cosmocc "$PBIN"/cosmoc++ "$PBIN"/cosmoar || return 1
	ln -s ../lib/cosmopolitan/bin/cosmocc "$PKGDEST/usr/bin/cosmocc" || return 1
	ln -s ../lib/cosmopolitan/bin/cosmoc++ "$PKGDEST/usr/bin/cosmoc++" || return 1
	ln -s ../lib/cosmopolitan/bin/cosmoar "$PKGDEST/usr/bin/cosmoar" || return 1
	ln -s ../lib/cosmopolitan/bin/apelink "$PKGDEST/usr/bin/apelink" || return 1
	# Docs + notices (ISC libc text always; GPL toolchain texts when present).
	mkdir -p "$PKGDEST/usr/share/doc/cosmopolitan" || return 1
	cp -- "$RECIPE_DIR/files/PROVENANCE.md" "$RECIPE_DIR/files/LOADER.md" \
		"$PKGDEST/usr/share/doc/cosmopolitan/" || return 1
	cp -- "$SRC/LICENSE" "$PKGDEST/usr/share/doc/cosmopolitan/LICENSE.cosmopolitan" || return 1
	for l in "$SRC"/tool/cosmocc/LICENSE*; do
		test -f "$l" && cp -- "$l" "$PKGDEST/usr/share/doc/cosmopolitan/" || true
	done
	# Housekeeping: no .la, no lib64, no docs duplicating native GCC.
	rm -f "$PKGDEST$COSMOPREFIX"/lib/*.la "$XLIB"/*.la "$ALIB"/*.la
	rm -rf "$PKGDEST$COSMOPREFIX"/share
	for lib64 in "$PKGDEST"/lib64 "$PKGDEST"/usr/lib64; do
		if [ -e "$lib64" ]; then
			echo "ERROR: forbidden lib64 path created: $lib64" >&2
			return 1
		fi
	done
	# No-overlap assert: nothing unprefixed that could shadow gcc/clang.
	bad=$(cd "$PBIN" && ls | grep -vxE '(x86_64|aarch64)-linux-cosmo-.*|(x86_64|aarch64|unknown)-unknown-cosmo-.*|cosmocc|cosmoc\+\+|cosmoar|apelink|fixupobj|zipcopy|pecheck|mktemper|mkdeps|tlscc|ape-x86_64\.elf|ape-aarch64\.elf|ape-x86_64\.macho|ape-m1\.c' || true)
	if [ -n "$bad" ]; then
		echo "ERROR: unexpected payload names in $COSMOPREFIX/bin (overlap risk):" >&2
		echo "$bad" >&2
		return 1
	fi
	if [ -e "$PBIN/gcc" ] || [ -e "$PBIN/cc" ] || [ -e "$PBIN/c++" ] \
		|| [ -e "$PBIN/ld" ] || [ -e "$PBIN/as" ] || [ -e "$PBIN/ar" ] \
		|| [ -e "$PBIN/clang" ]; then
		echo "ERROR: unprefixed compiler binary would shadow native gcc/clang" >&2
		return 1
	fi
	echo "install: layout complete, no overlap"

	# Stage 6: acceptance — one C source to a single dual-arch APE, both
	# embedded architectures verified, executed on Saphira via the STAGED
	# loader (no global install, no binfmt in this build).
	SMOKE=$BUILDDIR/smoke
	mkdir -p "$SMOKE" || return 1
	printf '%s\n' '#include <stdio.h>' 'int main(void){printf("hello cosmo\n");return 0;}' > "$SMOKE/hello.c"
	sh "$PBIN/cosmocc" -o "$SMOKE/hello" "$SMOKE/hello.c" \
		|| { echo "ERROR: cosmocc acceptance compile failed" >&2; return 1; }
	test -f "$SMOKE/hello" || { echo "ERROR: no APE output" >&2; return 1; }
	test -f "$SMOKE/hello.com.dbg" || { echo "ERROR: no x86_64 ELF companion" >&2; return 1; }
	test -f "$SMOKE/hello.aarch64.elf" || { echo "ERROR: no aarch64 ELF companion" >&2; return 1; }
	head -c 6 "$SMOKE/hello" | grep -q 'MZqFpD' \
		|| { echo "ERROR: APE magic MZqFpD missing" >&2; return 1; }
	grep -q 'jartsr' "$SMOKE/hello" \
		|| { echo "ERROR: APE shell magic jartsr missing" >&2; return 1; }
	[ "$(readelf -h "$SMOKE/hello.com.dbg" | grep 'Machine:' | grep -c 'X86-64')" -eq 1 ] \
		|| { echo "ERROR: x86_64 companion is not X86-64 ELF" >&2; return 1; }
	[ "$(readelf -h "$SMOKE/hello.aarch64.elf" | grep 'Machine:' | grep -c 'AArch64')" -eq 1 ] \
		|| { echo "ERROR: aarch64 companion is not AArch64 ELF" >&2; return 1; }
	"$PBIN/pecheck" "$SMOKE/hello" \
		|| { echo "ERROR: pecheck rejected the acceptance APE" >&2; return 1; }
	ls -l "$SMOKE/hello" "$SMOKE/hello.com.dbg" "$SMOKE/hello.aarch64.elf"
	sha256sum "$SMOKE/hello" "$SMOKE/hello.com.dbg" "$SMOKE/hello.aarch64.elf"
	"$PBIN/ape-x86_64.elf" "$SMOKE/hello" \
		|| { echo "ERROR: acceptance APE did not execute under the staged loader" >&2; return 1; }
	echo "acceptance: single dual-architecture APE built, verified and executed"
}

recipe_install()
{
	# Everything was installed to its final layout during recipe_build
	# (compilers via DESTDIR, runtime via explicit copies); the loader is
	# payload only and no maintainer script activates anything.
	:
}

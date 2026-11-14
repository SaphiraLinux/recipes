#!/bin/sh

pkgname=libc-test
# Snapshot date of the vendored upstream suite (commit below).
pkgver=20261101
pkgrel=18
pkgarch=${SAPHIRA_ARCH:-x86_64}
pkgdesc='musl libc-test suite + Saphira runner (validates the installed libc)'
license='MIT'
# Upstream is the musl project's libc-test (Szabolcs Nagy / nsz).
# Canonical project page https://repo.or.cz/libc-test.git is
# UK-blocked (git daemon refuses, pointing at /uk-blocked.html;
# verified from Egg 2026-11-11), so Saphira records and vendors
# from the owner's mirror below (byte-identical).
# Pinned commit (immutable; tarball made with git archive):
#   63e36e934e8f2bedf645303a90b64098e2af6c8f  (2026-11-01)
# Upstream licence: MIT (COPYRIGHT file). Math test vectors under
# BSD/GPL licences are data files only (src/math/ucb, src/math/crlibm).
libc_test_sha256=23762e39f6f5ceb307a42e5cd35065a8b7c3e0193311b8b1dcc8660e029a1339
origin=libc-test
repo=saphira
url=git://nsz.repo.hu:49100/repo/libc-test

depends="musl musl-static python3"
makedepends="
	binutils
	gcc
	make
	musl-static
"

subpackages=""

recipe_build()
{
	TBALL="$RECIPE_DIR/files/libc-test-63e36e934e8f.tar.gz"
	echo "$libc_test_sha256  $TBALL" | sha256sum -c -
	tar --no-same-owner -C "$SRC" --strip-components=1 -xf "$TBALL"
	# Saphira tests join the upstream tree (auto-discovered by the
	# upstream Makefile wildcard src/*/*.c; no upstream files touched).
	mkdir -p "$SRC/src/saphira"
	cp "$RECIPE_DIR"/files/saphira/*.c "$RECIPE_DIR"/files/saphira/*.mk "$SRC/src/saphira/"
	cp "$RECIPE_DIR/files/config.mak" "$SRC/config.mak"
	# Static toolchain for the static linkage variant. The path is
	# identical in the build root (via makedepends) and on the target,
	# so static test binaries provably exercise the packaged static
	# musl instead of whatever libc the builder seed carries.
	STATIC_CC=/opt/saphira/musl-static/bin/musl-static-gcc
	[ -x "$STATIC_CC" ] || {
		echo "musl-static toolchain missing ($STATIC_CC); musl-static must be in makedepends" >&2
		return 1
	}
	# Runtime test categories. api/ is excluded: those are
	# compile-only conformance checks with no per-test binary
	# (all objects link into a single api/main.exe), and they
	# reference _PC_TIMESTAMP_RESOLUTION / _SC_XOPEN_UUCP in ways
	# musl does not provide. common/ is the test harness itself.
	# musl/pleval is an upstream-disabled stub (its .mk neuters the
	# run). Only functional, regression, math and saphira ship.
	# Compile-only goals (never all/run/REPORT/*.err, which would
	# EXECUTE the suite via $(RUN_TEST)): per-test dynamic
	# `src/<cat>/<name>.exe`, per-test static
	# `src/<cat>/<name>-static.exe`, and the four helper DSOs
	# (*_dso.so) the dlopen/tls tests load at runtime.
	# Dynamic-only exceptions (upstream .mk + saphira_abi.mk):
	# these link or dlopen at runtime and have no static variant.
	DYN_ONLY=" functional/dlopen functional/tls_align_dlopen functional/tls_init_dlopen regression/tls_get_new-dtv saphira/saphira_abi "
	DYN_EXES=""; STATIC_EXES=""; DYN_SOS=""
	for d in functional regression math saphira; do
		for c in "$SRC"/src/$d/*.c; do
			[ -e "$c" ] || continue
			n=${c##*/}; n=${n%.c}
			t="$d/$n"
			case "$n" in
			*_dso)
				DYN_SOS="$DYN_SOS src/$t.so"
				continue
				;;
			esac
			DYN_EXES="$DYN_EXES src/$t.exe"
			case "$DYN_ONLY" in
			*" $t "*) ;;
			*) STATIC_EXES="$STATIC_EXES src/$t-static.exe" ;;
			esac
		done
	done
	[ -n "$DYN_EXES" ] || { echo "no dynamic test targets enumerated" >&2; return 1; }
	[ -n "$STATIC_EXES" ] || { echo "no static test targets enumerated" >&2; return 1; }
	case "$DYN_EXES" in *.exe*) : ;; *) echo "dynamic enumeration has no test binaries" >&2; return 1;; esac
	case "$STATIC_EXES" in *.exe*) : ;; *) echo "static enumeration has no test binaries" >&2; return 1;; esac
	# math ships static variants explicitly: upstream defaults
	# math.BINS_TEMPL to dynamic-only, but every test still has a
	# `%-static.exe` link rule, so requesting the targets builds
	# them with the same sources and flags as dynamic.
	# Two linkage trees, each building ONLY what it ships.
	# Upstream provides no per-linkage CC variable (both link rules
	# use $(CC)), so one invocation cannot build both; a pristine
	# second tree keeps each variant deterministic without
	# touching upstream rules.
	# (Never `make -B` here: it would rebuild config.mak from
	# config.mak.def, clobbering the Saphira flags appended above.)
	# Phase markers go to the build log so a slow build can be
	# attributed instead of guessed at.
	phase() { echo "libc-test build phase: $1 $(date +%T)" >&2; }
	phase "enumerate-done"
	SRC_STATIC="$SRC-static"
	rm -rf "$SRC_STATIC" && cp -a "$SRC" "$SRC_STATIC"
	# Static CC travels in the static tree's config.mak (file
	# assignment, last line wins), NEVER on the make command line.
	# GNU make auto-exports command-line definitions to recipe
	# children (proven: `make CC=X` shows $CC=X in the child shell),
	# and musl-static-gcc ends in `exec ${CC:-gcc}` — so a command-line
	# CC pointing at the wrapper makes the wrapper exec ITSELF, flags
	# accumulating forever, 100% CPU, zero outputs. A file-level CC is
	# not exported, so the wrapper falls back to gcc as designed.
	{ cat "$SRC/config.mak"; printf 'CC = %s\n' "$STATIC_CC"; } > "$SRC_STATIC/config.mak"
	phase "trees-ready"
	# Dynamic variant (system compiler, exercises the installed libc)
	# and static variant (Saphira static toolchain, hermetic checks)
	# build SERIALLY in separate trees: the trees share nothing, and
	# serial keeps failure attribution trivial (one log, one rc).
	# The whole upstream compile is seconds-scale; there is nothing
	# worth parallelizing here. Explicit binary goals only (unquoted
	# lists split into goals intentionally). Upstream link/compile
	# rules echo BUILDERROR but exit 0, so a clean make exit proves
	# nothing: the per-tree checks below grep each log for a
	# line-start BUILDERROR (the echoed recipe text itself contains
	# the word, so an unanchored grep false-positives on every
	# compile line) and verify every expected file exists.
	# Verbose make output stays: it is the only progress signal, and
	# the line-anchored grep keeps it honest.
	cd "$SRC"
	make -j${JOBS:-$(nproc)} $DYN_EXES $DYN_SOS >"$SRC/build.log" 2>&1 || return 1
	phase "dynamic-done"
	if grep -q '^BUILDERROR ' "$SRC/build.log"; then
		echo "dynamic build had BUILDERROR failures (see build.log):" >&2
		grep '^BUILDERROR ' "$SRC/build.log" >&2
		return 1
	fi
	for t in $DYN_EXES $DYN_SOS; do
		[ -f "$SRC/$t" ] || { echo "dynamic build missing expected $t" >&2; return 1; }
	done
	# Static tree ships only *-static.exe (nothing built only to be
	# discarded); same sources, same rules, same failure checks.
	cd "$SRC_STATIC"
	make -j${JOBS:-$(nproc)} $STATIC_EXES >"$SRC_STATIC/build-static.log" 2>&1 || return 1
	phase "static-done"
	if grep -q '^BUILDERROR ' "$SRC_STATIC/build-static.log"; then
		echo "static build had BUILDERROR failures (see build-static.log):" >&2
		grep '^BUILDERROR ' "$SRC_STATIC/build-static.log" >&2
		return 1
	fi
	for t in $STATIC_EXES; do
		[ -f "$SRC_STATIC/$t" ] || { echo "static build missing expected $t" >&2; return 1; }
	done
	phase "verify-done"
	# Test inventory: logical "category/name" per test SOURCE (api/ and
	# common/ excluded: api tests are compile-time checks with no
	# per-test binary, common/ holds the test library itself).
	# Missing binaries at runtime become SKIP rows, never silent.
	: > "$SRC/test-list.txt"
	for d in functional regression math saphira; do
		for c in "$SRC"/src/$d/*.c; do
			[ -e "$c" ] || continue
			t=${c#$SRC/src/}; t=${t%.c}
			echo "$t"
		done
	done | sort -u > "$SRC/test-list.txt"
	# Coverage map: test binary -> libc symbols it calls (undefined
	# dynsyms). Honest call-graph inventory, not a semantic claim.
	# Dynamic tree only: static binaries expose no dynamic symbols.
	: > "$SRC/coverage.map"
	for b in $(find "$SRC/src" -name '*.exe' -a ! -name '*-static.exe' -type f | sort); do
		t=${b#$SRC/src/}; t=${t%.exe}; t=${t%-static}
		nm -D -u "$b" 2>/dev/null | awk '$1=="U"{print $2}' | grep -v '^_' | sort -u | tr '\n' ' ' | sed "s|^|$t: |" >> "$SRC/coverage.map" || true
	done
	# Symbol universe from the build root libc (complement source for
	# the untested set; see runner notes on build/target skew).
	SOLIB=$(gcc -print-file-name=libc.so 2>/dev/null || echo /lib/libc.so)
	nm -D --defined-only "$SOLIB" 2>/dev/null | awk '$2=="T"||$2=="W"||$2=="D"||$2=="B" {print $3}' | sort -u > "$SRC/symbols.txt" || : > "$SRC/symbols.txt"
	# Build manifest for the runner report.
	# NOTE: never `cmd | head -1` on a live pipe here. head exits after
	# one line and the writer dies of SIGPIPE (rc=141) under the
	# builder's errexit+pipefail. Stage through temp files instead:
	# head on a regular file has no live writer to kill.
	gcc --version >"$SRC/cc-version.txt" 2>/dev/null
	ld -v >"$SRC/ld-version.txt" 2>&1
	{
		echo "{"
		echo "  \"suite\": \"libc-test\","
		echo "  \"suite_commit\": \"63e36e934e8f2bedf645303a90b64098e2af6c8f\","
		echo "  \"suite_date\": \"2026-11-01\","
		echo "  \"tarball_sha256\": \"$libc_test_sha256\","
		printf '  "cc": "'
		head -1 "$SRC/cc-version.txt" | tr -d '"\n'
		echo '",'
		printf '  "ld": "'
		head -1 "$SRC/ld-version.txt" | tr -d '"\n'
		echo '",'
		echo "  \"cflags\": \"$(grep -h . "$SRC/config.mak" | tr '\n' ' ' | tr -d '\"')\","
		echo "  \"static_cc\": \"/opt/saphira/musl-static/bin/musl-static-gcc\","
		echo "  \"arch\": \"$pkgarch\""
		echo "}"
	} > "$SRC/build-info.json"
	# Saphira: compare runner outputs against the pinned baseline.
	# (Baseline generated from a validation run; see files/baseline.json.)
}

recipe_install()
{
	R="$PKGDEST/usr/share/libc-test"
	install -d -m 0755 "$R/bin"
	# Test binaries + their helper DSOs, preserving subdir layout.
	# Dynamic binaries (system-toolchain tree) exercise the installed
	# libc; static binaries (musl-static tree) are hermetic checks
	# against the packaged static musl. Only the four runtime
	# categories ship: api/ (compile-only checks), common/
	# (harness) and musl/ (upstream-disabled stub) never install.
	SRC_STATIC="$SRC-static"
	for f in $(cd "$SRC" && find src/functional src/regression src/math src/saphira \( -name '*.exe' -a ! -name '*-static.exe' \) | sort); do
		install -D -m 0755 "$SRC/$f" "$R/bin/${f#src/}" || return 1
	done
	for f in $(cd "$SRC" && find src/functional src/regression src/math src/saphira -name '*_dso.so' | sort); do
		install -D -m 0755 "$SRC/$f" "$R/bin/${f#src/}" || return 1
	done
	for f in $(cd "$SRC_STATIC" && find src/functional src/regression src/math src/saphira -name '*-static.exe' | sort); do
		install -D -m 0755 "$SRC_STATIC/$f" "$R/bin/${f#src/}" || return 1
	done
	unset f
	install -m 0644 "$SRC/build-info.json" "$R/"
	install -m 0644 "$SRC/coverage.map" "$R/"
	install -m 0644 "$SRC/symbols.txt" "$R/"
	install -m 0644 "$SRC/test-list.txt" "$R/"
	install -m 0644 "$RECIPE_DIR/files/baseline.json" "$R/"
	install -d -m 0755 "$PKGDEST/usr/bin"
	install -m 0755 "$RECIPE_DIR/files/libc-test-run" "$PKGDEST/usr/bin/libc-test-run"
	install -m 0755 "$RECIPE_DIR/files/libc-test-musl-check" "$PKGDEST/usr/bin/libc-test-musl-check"
	# Sinew F4 benchmark suite: self-contained sources + driver, runnable
	# from the installed path with no /recipes access. Sources stay
	# read-only (0644); the driver is executable (0755). Scratch goes to
	# ${SAPHIRA_TMPDIR:-/build/tmp}; override on hosts where /build is
	# not writable (the driver aborts with instructions otherwise).
	# Results land in the scratch dir, never in the package tree.
	BENCH="$PKGDEST/usr/share/libc-test/bench-f4"
	install -d -m 0755 "$BENCH/src"
	install -m 0755 "$RECIPE_DIR/tests/sinew-bench-f4/bench-f4.sh" "$BENCH/"
	for f in "$RECIPE_DIR"/tests/sinew-bench-f4/src/*.[ch]; do
		install -m 0644 "$f" "$BENCH/src/" || return 1
	done
	unset f
	# No suite execution here: recipe_install ships the runner and musl-check only.
	# Run on the target: libc-test-run [--jsonl FILE] [--baseline FILE]
}

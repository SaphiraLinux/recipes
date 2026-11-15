# Saphira Linux
# Copyright (c) 2026 AKADATA LIMITED
# SPDX-License-Identifier: MIT
#!/bin/sh
# ftw legacy-follow + nftw CHDIR regression (Sinew Item 19).
# Fixture tree under scratch; no mounts, no namespaces, no host writes.
# Fails on libc without 0036 (legacy ftw passes FTW_PHYS: symlinks not
# followed) and without 0037 (FTW_CHDIR silently ignored: callbacks run
# with the caller directory instead of the visited one).
#
# RED check (the harness must fail loudly on wrong expectations):
# change any expected count or cwd below and the run must report
# FAIL with a non-zero exit. Verified RED at landing against r22.
set -eu
if ! command -v cc >/dev/null 2>&1; then
	echo "SKIP no C compiler"
	exit 0
fi
if [ -n "${SAPHIRA_TMPDIR:-}" ]; then
	scratch_base=$SAPHIRA_TMPDIR
elif [ -d /build/tmp ] && [ -w /build/tmp ]; then
	scratch_base=/build/tmp
else
	scratch_base=/tmp
fi
root=$scratch_base/ftw-legacy-chdir-test-$$
mkdir -p "$root/fix"
trap 'rm -rf "$root"' EXIT INT TERM
CC=${CC:-cc}
# TU_EXTRA_OBJS: optional extra objects on the probe link line (used to
# verify candidate nftw.o/ftw.o translation units without a release).
cat > "$root/t.c" <<'EOF'
#define _GNU_SOURCE
#include <ftw.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <limits.h>
#include <sys/stat.h>
static int nF, nD, nSL, nSLN, nDNR;
static int cb(const char *f, const struct stat *sb, int tf, struct FTW *w) {
	(void)sb; (void)w;
	if (tf == FTW_F) nF++;
	else if (tf == FTW_D) nD++;
	else if (tf == FTW_SL) nSL++;
#ifdef FTW_SLN
	else if (tf == FTW_SLN) nSLN++;
#endif
	else if (tf == FTW_DNR) nDNR++;
	printf("V tf=%d f=%s\n", tf, f);
	return 0;
}
static int cb3(const char *f, const struct stat *sb, int tf) {
	return cb(f, sb, tf, 0);
}
static int cb_cwd(const char *f, const struct stat *sb, int tf, struct FTW *w) {
	char c[PATH_MAX]; (void)sb; (void)tf; (void)w;
	getcwd(c, sizeof c);
	printf("W f=%s cwd=%s\n", f, c);
	return 0;
}
static int cb_abort(const char *f, const struct stat *sb, int tf, struct FTW *w) {
	static int n = 0; (void)f; (void)sb; (void)tf; (void)w;
	if (++n == 3) return 7;
	return 0;
}
int main(int argc, char **argv) {
	const char *dir = argv[1];
	if (!strcmp(argv[2], "legacy")) {
		int r = ftw(dir, cb3, 10);
		printf("SUMMARY r=%d F=%d D=%d SL=%d SLN=%d DNR=%d\n",
			r, nF, nD, nSL, nSLN, nDNR);
		return 0;
	}
	if (!strcmp(argv[2], "walk")) {
		char start[PATH_MAX], end[PATH_MAX];
		getcwd(start, sizeof start);
		int r = nftw(dir, cb_cwd, 10, FTW_PHYS | FTW_CHDIR);
		getcwd(end, sizeof end);
		printf("SUMMARY r=%d start=%s end=%s same=%d\n",
			r, start, end, !strcmp(start, end));
		return 0;
	}
	if (!strcmp(argv[2], "depth")) {
		char start[PATH_MAX], end[PATH_MAX];
		getcwd(start, sizeof start);
		int r = nftw(dir, cb_cwd, 10, FTW_PHYS | FTW_CHDIR | FTW_DEPTH);
		getcwd(end, sizeof end);
		printf("SUMMARY r=%d start=%s end=%s same=%d\n",
			r, start, end, !strcmp(start, end));
		return 0;
	}
	if (!strcmp(argv[2], "abort")) {
		char start[PATH_MAX], end[PATH_MAX];
		getcwd(start, sizeof start);
		int r = nftw(dir, cb_abort, 10, FTW_PHYS | FTW_CHDIR);
		getcwd(end, sizeof end);
		printf("SUMMARY r=%d same=%d\n", r, !strcmp(start, end));
		return 0;
	}
	return 2;
}
EOF
$CC -O2 -Wall -o "$root/t" "$root/t.c" ${TU_EXTRA_OBJS:-}
fails=0
ck() { # ck <name> <expected-fixed-string-pattern...> : grep -qF on output
	name=$1; shift
	if grep -qF "$1" "$root/out"; then
		echo "ok $name"
	else
		echo "FAIL $name (want: $1)"
		fails=$((fails + 1))
	fi
}
# Fixture: root/{file1, sub/{file2, l_file->../file1, dangling}, l_sub->sub, noaccess/{inner}}
mkdir -p "$root/fix/sub" "$root/fix/noaccess"
echo hi > "$root/fix/file1"
echo yo > "$root/fix/sub/file2"
ln -s ../file1 "$root/fix/sub/l_file"
ln -s nosuch "$root/fix/sub/dangling"
ln -s sub "$root/fix/l_sub"
echo hid > "$root/fix/noaccess/inner"
chmod 000 "$root/fix/noaccess"
R=$root/fix

echo "=== legacy ftw follows symlinks (0036) ==="
"$root/t" "$R" legacy > "$root/out"
# file1, file2, l_file(followed), l_sub/file2, l_sub/l_file; dangling
# seen twice (once per path: sub + l_sub re-walk, same as nftw follow)
ck legacy-follow "SUMMARY r=0 F=5 D=3 SL=0 SLN=2 DNR=1"
echo "=== nftw CHDIR preorder (0037) ==="
START=$PWD
"$root/t" "$R" walk > "$root/out"
ck walk-rc "same=1"
ck walk-root-pre "W f=$R cwd=$START"
ck walk-sub-pre "W f=$R/sub cwd=$R"
ck walk-file2 "W f=$R/sub/file2 cwd=$R/sub"
echo "=== nftw CHDIR depth (0037) ==="
"$root/t" "$R" depth > "$root/out"
ck depth-rc "same=1"
ck depth-sub-post "W f=$R/sub cwd=$R/sub"
ck depth-root-post "W f=$R cwd=$R"
echo "=== nftw CHDIR abort restores cwd (0037) ==="
"$root/t" "$R" abort > "$root/out"
ck abort-restore "SUMMARY r=7 same=1"
chmod -R u+rwX "$root/fix"
if [ "$fails" -ne 0 ]; then
	echo "RESULT: $fails FAILURES"
	exit 1
fi
echo "RESULT: ALL PASS"

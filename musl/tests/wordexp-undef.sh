#!/bin/sh
# wordexp WRDE_UNDEF forkless-check regression (Sinew 0020).
# Tests the HOST libc: fails on musl without 0020 (UNDEF ignored),
# passes with 0020 applied. Hermetic scratch under SAPHIRA_TMPDIR.
# Expectations per POSIX SUSv3 (UNDEF=error on attempt to expand an
# unset variable): top-level unset attempts -> BADVAL with zero
# command side effects; defaults/guards/namespaces respected;
# command-substitution interiors exempt (glibc-measured H4);
# NOCMD scanner keeps precedence; malformed input stays SYNTAX.
set -eu
root=${SAPHIRA_TMPDIR:-/build/tmp}/wordexp-undef-test-$$
mkdir -p "$root/can"
trap 'rm -rf "$root"' EXIT INT TERM
cat > "$root/t.c" <<'EOF'
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <dirent.h>
#include <wordexp.h>
static const char *CD;
static int fails = 0;
static const char *rn(int r) {
	switch (r) {
	case 0: return "0";
	case WRDE_NOSPACE: return "NOSPACE";
	case WRDE_BADCHAR: return "BADCHAR";
	case WRDE_BADVAL: return "BADVAL";
	case WRDE_CMDSUB: return "CMDSUB";
	case WRDE_SYNTAX: return "SYNTAX";
	default: return "?";
	}
}
static void mkcan(const char *m) {
	char p[256];
	snprintf(p, sizeof p, "%s/%s", CD, m);
	unlink(p);
}
static void check(const char *in, int flags, int want) {
	wordexp_t wm;
	int r;
	memset(&wm, 0, sizeof wm);
	r = wordexp(in, &wm, flags);
	if (r == 0)
		wordfree(&wm);
	if (r != want) {
		printf("FAIL [%d] \"%s\": got %s want %s\n",
			flags, in, rn(r), rn(want));
		fails++;
		return;
	}
	printf("ok [%d] \"%s\" -> %s\n", flags, in, rn(r));
}
static void checkwords(const char *in, const char *w0) {
	wordexp_t wm;
	int r;
	memset(&wm, 0, sizeof wm);
	r = wordexp(in, &wm, WRDE_UNDEF);
	if (r != 0 || wm.we_wordc < 1 ||
	    strcmp(wm.we_wordv[0], w0) != 0) {
		printf("FAIL words \"%s\": ret=%s n=%lu\n", in, rn(r),
			(unsigned long)(r == 0 ? wm.we_wordc : 0));
		fails++;
		if (r == 0)
			wordfree(&wm);
		return;
	}
	wordfree(&wm);
	printf("ok words \"%s\" -> [\"%s\"]\n", in, w0);
}
int main(int argc, char **argv) {
	DIR *dd;
	struct dirent *de;
	(void)argc;
	CD = argv[1];
	unsetenv("UNSET");
	unsetenv("Q");
	unsetenv("UQ");
	unsetenv("A_UNSET_VAR");
	unsetenv("Y");
	unsetenv("A");
	unsetenv("B");
	unsetenv("U1");
	unsetenv("Z");
	setenv("X", "ex", 1);
	unsetenv("FOO");
	setenv("X", "ex", 1);
	setenv("SET", "yes", 1);
	setenv("SET0", "", 1);
	/* Unset attempts must fail closed, without executing. */
	check("$UNSET", WRDE_UNDEF, WRDE_BADVAL);
	check("x $UNSET y", WRDE_UNDEF, WRDE_BADVAL);
	check("${UNSET}", WRDE_UNDEF, WRDE_BADVAL);
	check("\"$UNSET\"", WRDE_UNDEF, WRDE_BADVAL);
	check("${X+$UNSET}", WRDE_UNDEF, WRDE_BADVAL);
	check("${#UNSET}", WRDE_UNDEF, WRDE_BADVAL);
	check("${UNSET%X}", WRDE_UNDEF, WRDE_BADVAL);
	check("${X#$UNSET}", WRDE_UNDEF, WRDE_BADVAL);
	check("$(($UNSET+1))", WRDE_UNDEF, WRDE_BADVAL);
	check("${UNSET:?boom}", WRDE_UNDEF, WRDE_BADVAL);
	check("${SET0:-$UNSET}", WRDE_UNDEF, WRDE_BADVAL);
	check("${A_UNSET_VAR:-${UNSET}}", WRDE_UNDEF, WRDE_BADVAL);
	mkcan("M1");
	check("$(touch M1) $UNSET", WRDE_UNDEF, WRDE_BADVAL);
	mkcan("M2");
	check("$UNSET $(touch M2)", WRDE_UNDEF, WRDE_BADVAL);
	mkcan("M3");
	check("`touch M3` $UNSET", WRDE_UNDEF, WRDE_BADVAL);
	/* Defaults, guards and set variables: no error. */
	checkwords("${UNSET-def}", "def");
	checkwords("${UNSET-$X}", "ex");
	checkwords("${UNSET=$X}", "ex");
	checkwords("${X-$UNSET}", "ex");
	checkwords("${SET:-$UNSET}", "yes");
	checkwords("${X=1} $X", "ex");
	checkwords("${UQ=1} $UQ", "1");
	check("x $UNSET y", 0, 0);
	/* Command-substitution interiors exempt (H4). */
	checkwords("$(echo x $UNSET) y", "x");
	/* NOCMD scanner keeps precedence; malformed stays SYNTAX. */
	check("$UNSET ) $UNSET", WRDE_UNDEF|WRDE_NOCMD, WRDE_BADCHAR);
	check("$UNSET $(echo $UNSET", WRDE_UNDEF|WRDE_NOCMD, WRDE_CMDSUB);
	check("\"${X-\"$\"Y}\"", WRDE_UNDEF|WRDE_NOCMD, 0);
	check("${UNSET", WRDE_UNDEF, WRDE_SYNTAX);
	/* Class-B (0021): quote-first "$" is transparent in quoted-context
	 * brace words (Q is unset here, so defaults are taken); dollar-first
	 * $" opens a locale string whose content still expands; in-dq $"
	 * stays literal; arithmetic digit-led tokens are numbers, never
	 * variables. Probes with X verify take-suppression (X=ex is set). */
	check("\"${Q-\"$\"Y}\"", WRDE_UNDEF|WRDE_NOCMD, WRDE_BADVAL);
	checkwords("\"${X-\"$\"Y}\"", "ex");
	check("\"${A-\"$\"Y}\"", WRDE_UNDEF|WRDE_NOCMD, WRDE_BADVAL);
	check("\"${Q:-\"$\"Y}\"", WRDE_UNDEF|WRDE_NOCMD, WRDE_BADVAL);
	check("\"${Q-\"$\"b(1+1))}\"", WRDE_UNDEF|WRDE_NOCMD, WRDE_BADVAL);
	check("\"${Q:=\"$\"U1}\"", WRDE_UNDEF|WRDE_NOCMD, WRDE_BADVAL);
	check("\"${Q-\"${Y-\"$\"Z}\"}\"", WRDE_UNDEF|WRDE_NOCMD, WRDE_BADVAL);
	checkwords("$((1+1))", "2");
	checkwords("$\"foo\"", "foo");
	check("$\"$UNSET\"", WRDE_UNDEF, WRDE_BADVAL);
	checkwords("\"$\"Y", "$Y");
	checkwords("${Q-\"$\"Y}", "$Y");
	check("\"${UNSET-'$UNSET}\"", WRDE_UNDEF|WRDE_NOCMD, WRDE_SYNTAX);
	/* Zero command side effects on every UNDEF failure above:
	 * no canary file may exist. Normal execution (no UNDEF or
	 * clean expansion) is unaffected. */
	if ((dd = opendir(CD)) != NULL) {
		while ((de = readdir(dd)) != NULL) {
			if (de->d_name[0] == '.')
				continue;
			printf("FAIL side effect: %s/%s exists\n",
				CD, de->d_name);
			fails++;
		}
		closedir(dd);
	}
	if (fails) {
		printf("RESULT: %d FAILURES\n", fails);
		return 1;
	}
	printf("RESULT: ALL PASS\n");
	return 0;
}
EOF
cc -O2 -Wall -o "$root/t" "$root/t.c"
# Locale independence: the checker is byte-oriented and getenv-based,
# so C and C.UTF-8 (the only locales musl exposes) must agree exactly.
# A third generation (Turkish dotted-I style traps in other
# implementations) is covered by the byte-oriented design; homer
# provides the glibc-locale comparison side.
for loc in C C.UTF-8; do
	echo "== locale $loc =="
	cd "$root/can" && LANG=$loc LC_ALL=$loc "$root/t" "$root/can" </dev/null || exit 1
done

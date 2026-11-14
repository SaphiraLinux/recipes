#!/bin/sh
# floatscan NaN sign + payload pins (Sinew 0032 sign / Item 7a payload).
# Sign part: RED without 0032, GREEN with it (see below).
# Payload part: musl-native bare-NAN pins (DOCUMENTED divergence, not
# a defect). POSIX/C11 require nan(tag) == strtod("NAN(tag)") but leave
# the tagp->representation mapping unspecified ("used in an
# unspecified manner", man-pages nan.3; glibc documents its integer-
# mantissa choice in strtod.3 VERSIONS). musl chooses bare quiet NaN
# everywhere (nan.c is `return NAN`; floatscan consumes but discards
# the n-char sequence); glibc preserves payload bits. Both satisfy the
# equivalence; only the mapping differs. These pins lock musl's
# documented behaviour (bare + signs + endptr/errno) so a future
# floatscan change cannot silently alter it.
#
# CRITICAL: tags are runtime strings (mutable char arrays), never
# literals: GCC constant-folds nan("literal") at compile time, which
# would pin the compiler instead of libc.
# Tests the HOST libc: fails on musl without 0032 (__floatscan drops
# the sign on all NaN paths), passes with 0032 applied.
# Hermetic scratch under SAPHIRA_TMPDIR.
#
# POSIX.1-2024 XSH strtod: the subject sequence carries an optional
# sign and "if the subject sequence begins with a <hyphen-minus>,
# the sequence shall be interpreted as negated" while NAN "shall be
# interpreted as a quiet NaN". INFINITY already applies the sign, so
# NaN dropping it is a plain defect, not a parity choice.
set -eu
root=${SAPHIRA_TMPDIR:-/build/tmp}/nan-sign-test-$$
mkdir -p "$root"
trap 'rm -rf "$root"' EXIT INT TERM
cat > "$root/t.c" <<'EOF'
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <wchar.h>
static int fails = 0;
static void check(int cond, const char *name) {
	if (!cond) { printf("FAIL %s\n", name); fails++; }
	else printf("ok %s\n", name);
}
int main(void) {
	/* strto family: sign bit must follow the input sign. */
	check(signbit(strtof("-nan", 0)) != 0, "strtof -nan");
	check(signbit(strtof("nan", 0)) == 0, "strtof +nan");
	check(signbit(strtod("-nan", 0)) != 0, "strtod -nan");
	check(signbit(strtod("nan", 0)) == 0, "strtod +nan");
	check(signbit(strtold("-nan", 0)) != 0, "strtold -nan");
	check(signbit(strtold("nan", 0)) == 0, "strtold +nan");
	check(signbit(strtof("-NAN(abc)", 0)) != 0, "strtof -nan(abc)");
	check(signbit(strtod("-NAN(1)", 0)) != 0, "strtod -nan(1)");
	check(signbit(wcstof(L"-nan", 0)) != 0, "wcstof -nan");
	check(signbit(wcstod(L"-nan", 0)) != 0, "wcstod -nan");
	check(signbit(wcstold(L"-nan", 0)) != 0, "wcstold -nan");
	/* scanf family shares __floatscan: %f and %La spot checks. */
	{
		float f = 0; int r = sscanf("-nan", "%f", &f);
		check(r == 1 && signbit(f) != 0, "sscanf %f -nan");
	}
	{
		double d = 0; int r = sscanf("-nan", "%lf", &d);
		check(r == 1 && signbit(d) != 0, "sscanf %lf -nan");
	}
	{
		long double ld = 0; int r = sscanf("-nan", "%Lf", &ld);
		check(r == 1 && signbit(ld) != 0, "sscanf %Lf -nan");
	}
	/* Item 7a payload pins: musl-native bare quiet NaN.
	 * Runtime tag strings defeat GCC constant-folding of nan(). */
	{
		static const char *tags[] = {"", "123", "0xABC", "xyz", "!"};
		size_t i;
		for (i = 0; i < sizeof tags / sizeof *tags; i++) {
			char tag[16], pat[32];
			double d1, d2;
			float f1;
			char *e = 0;
			int er;
			snprintf(tag, sizeof tag, "%s", tags[i]);
			/* nan(tag) is bare, unsigned */
			d1 = nan(tag);
			check(isnan(d1) && signbit(d1) == 0, "nan bare");
			/* equivalence nan(tag) == strtod("NAN(tag)") holds
			 * (bitwise: == is always false for NaN) */
			snprintf(pat, sizeof pat, "NAN(%s)", tag);
			errno = 0; d2 = strtod(pat, &e); er = errno;
			check(isnan(d2) && !memcmp(&d1, &d2, sizeof d1),
			      "equiv bare");
			check(er == 0, "payload errno");
			/* float entry agrees too */
			errno = 0; f1 = strtof(pat, 0); er = errno;
			check(isnan(f1) && signbit(f1) == 0 && er == 0,
			      "strtof bare");
		}
		/* consumption runs through ')', tail intact, no errno */
		{
			char *e = 0;
			int er;
			double d;
			errno = 0; d = strtod("NAN(123)xyz", &e); er = errno;
			check(isnan(d) && e && !strcmp(e, "xyz") && er == 0,
			      "NAN consumption");
		}
		/* signs still applied through payload forms (0032 guard) */
		check(signbit(strtod("-NAN(123)", 0)) != 0, "-NAN(123)");
		check(signbit(strtof("-NAN(123)", 0)) != 0, "-NAN(123)f");
		{
			float f = 0; int r = sscanf("NAN(123)", "%f", &f);
			check(r == 1 && isnan(f), "sscanf NAN(123)");
		}
	}
	if (fails) {
		printf("RESULT: %d FAILURES\n", fails);
		return 1;
	}
	printf("RESULT: ALL PASS\n");
	return 0;
}
EOF
cc -O2 -Wall -o "$root/t" "$root/t.c" -lm
"$root/t" </dev/null

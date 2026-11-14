#!/bin/sh
# strptime %s epoch calendar-range audit (Sinew 0019).
# Tests the HOST libc: fails on musl without 0019 (%s is parse-only),
# passes with 0019 applied. Hermetic scratch under SAPHIRA_TMPDIR.
#
# Coverage: 2038 pair, 2106 pair, 9999, pre-1970 (day boundary,
# leap day, INT32_MIN), year 1, +/-1M years, guard-boundary
# rejections (true limit is tm_year fitting int), 64-bit limit
# rejections, DST spring-forward/fall-back + anchors with
# explicit US rules (bare rule-less TZ names are a musl TZ-parser
# matter, out of scope: the converter shares localtime's path).
set -eu
root=${SAPHIRA_TMPDIR:-/build/tmp}/strptime-s-test-$$
mkdir -p "$root"
trap 'rm -rf "$root"' EXIT INT TERM
cat > "$root/t.c" <<'EOF'
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
static int fails = 0;
static void check(const char *tz, const char *in,
		int y, int mo, int d, int h, int mi, int s,
		int wday, int yday, int isdst, long gmtoff) {
	struct tm tm;
	const char *r;
	memset(&tm, 0, sizeof tm);
	setenv("TZ", tz, 1);
	tzset();
	r = strptime(in, "%s", &tm);
	if (!r || *r) {
		printf("FAIL [%s] \"%s\": no/partial parse\n", tz, in);
		fails++;
		return;
	}
	if (tm.tm_year != y - 1900 || tm.tm_mon != mo - 1 ||
	    tm.tm_mday != d || tm.tm_hour != h ||
	    tm.tm_min != mi || tm.tm_sec != s ||
	    tm.tm_wday != wday || tm.tm_yday != yday ||
	    tm.tm_isdst != isdst || tm.tm_gmtoff != gmtoff) {
		printf("FAIL [%s] \"%s\": got %d-%02d-%02d %02d:%02d:%02d"
			" wday=%d yday=%d isdst=%d gmtoff=%ld\n",
			tz, in, tm.tm_year + 1900, tm.tm_mon + 1,
			tm.tm_mday, tm.tm_hour, tm.tm_min, tm.tm_sec,
			tm.tm_wday, tm.tm_yday,
			tm.tm_isdst, tm.tm_gmtoff);
		fails++;
		return;
	}
	printf("ok [%s] \"%s\"\n", tz, in);
}
static void check_fail(const char *tz, const char *in) {
	struct tm tm;
	const char *r;
	memset(&tm, 0, sizeof tm);
	setenv("TZ", tz, 1);
	tzset();
	r = strptime(in, "%s", &tm);
	if (r) {
		printf("FAIL [%s] \"%s\": expected reject\n", tz, in);
		fails++;
		return;
	}
	printf("ok [%s] \"%s\" rejected\n", tz, in);
}
int main(void) {
	const char *U = "UTC0";
	const char *E = "EST5EDT,M3.2.0,M11.1.0";
	check(U, "683078400", 1991, 8, 25, 0, 0, 0, 0, 236, 0, 0);
	check(U, "0", 1970, 1, 1, 0, 0, 0, 4, 0, 0, 0);
	check(U, "-1", 1969, 12, 31, 23, 59, 59, 3, 364, 0, 0);
	check(U, "2147483647", 2038, 1, 19, 3, 14, 7, 2, 18, 0, 0);
	check(U, "2147483648", 2038, 1, 19, 3, 14, 8, 2, 18, 0, 0);
	check(U, "4294967295", 2106, 2, 7, 6, 28, 15, 0, 37, 0, 0);
	check(U, "4294967296", 2106, 2, 7, 6, 28, 16, 0, 37, 0, 0);
	check(U, "253402300799", 9999, 12, 31, 23, 59, 59, 5, 364, 0, 0);
	check(U, "-86400", 1969, 12, 31, 0, 0, 0, 3, 364, 0, 0);
	check(U, "-58060800", 1968, 2, 29, 0, 0, 0, 4, 59, 0, 0);
	check(U, "-2147483648", 1901, 12, 13, 20, 45, 52, 5, 346, 0, 0);
	check(U, "-62135596800", 1, 1, 1, 0, 0, 0, 1, 0, 0, 0);
	check(U, "31494799166400", 1000000, 6, 15, 12, 0, 0, 4, 166, 0, 0);
	check(U, "-31619104833600", -1000000, 6, 15, 12, 0, 0, 4, 166, 0, 0);
	check_fail(U, "");
	check_fail(U, "-");
	check_fail(U, "+");
	check_fail(U, "abc");
	check_fail(U, "67908586878892800");
	check_fail(U, "-67908586910515200");
	check_fail(U, "67908586878892801");
	check_fail(U, "-67908586910515201");
	check_fail(U, "100000000000000000");
	check_fail(U, "9223372036854775807");
	check_fail(U, "-9223372036854775808");
	check_fail(U, "9223372036854775808");
	check_fail(U, "18446744073709551615");
	check(E, "1772953199", 2026, 3, 8, 1, 59, 59, 0, 66, 0, -18000);
	check(E, "1772953200", 2026, 3, 8, 3, 0, 0, 0, 66, 1, -14400);
	check(E, "1793512799", 2026, 11, 1, 1, 59, 59, 0, 304, 1, -14400);
	check(E, "1793512800", 2026, 11, 1, 1, 0, 0, 0, 304, 0, -18000);
	check(E, "1782907200", 2026, 7, 1, 8, 0, 0, 3, 181, 1, -14400);
	check(E, "1767268800", 2026, 1, 1, 7, 0, 0, 4, 0, 0, -18000);
	if (fails) {
		printf("RESULT: %d FAILURES\n", fails);
		return 1;
	}
	printf("RESULT: ALL PASS\n");
	return 0;
}
EOF
cc -O2 -Wall -o "$root/t" "$root/t.c"
"$root/t" </dev/null

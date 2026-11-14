/* F4 regex: mirrors the exact failing upstream assertions, unweakened,
 * plus regcomp/regexec throughput on fixed patterns.
 *
 * CORRECTNESS (same assertions as the suite, same expected values):
 * - regression/regex-backref-oob.c:34 BRE with multibyte chars must match.
 * - regression/regexec-backref.c:14-26 backref submatch offsets must be
 *   (1,2) for "foo" and (1,3) for "aababa".
 * Each probe reports got-vs-want; a lib that fails them fails this binary
 * exactly the way it fails the suite (no assertion is relaxed).
 */
#include "bench_common.h"
#include <locale.h>
#include <regex.h>

#ifndef BENCH_LINK
#define BENCH_LINK "dynamic"
#endif

#define BATCHES 21

static int fails;

static void verify_regex(void)
{
	/* Upstream regression/regex-backref-oob.c: exact pattern, input
	 * bytes and expected offsets. Locale pinned to C.UTF-8. */
	{
		char pat[] = "\\(a\\|b\\|..*\\)_\\1\\(.\\)\\2";
		char input[] = "ab_\xf1\x81\x81\x81_\xf1\x81\x81\x81__";
		regex_t r;
		regmatch_t rm[3];
		int n;
		setlocale(LC_ALL, "C.UTF-8");
		n = regcomp(&r, pat, 0);
		if (n) {
			printf("{\"suite\":\"sinew-bench-f4\",\"probe\":\"oob-regcomp\",\"rc\":%d}\n", n);
			fails++;
		} else {
			n = regexec(&r, input, 3, rm, 0);
			if (n || rm[0].rm_so != 3 || rm[0].rm_eo != 14 ||
			    rm[1].rm_so != 3 || rm[1].rm_eo != 7 ||
			    rm[2].rm_so != 12 || rm[2].rm_eo != 13) {
				printf("{\"suite\":\"sinew-bench-f4\",\"probe\":\"oob-regexec\","
					"\"rc\":%d,\"got\":\"(%ld,%ld)(%ld,%ld)(%ld,%ld)\","
					"\"want\":\"(3,14)(3,7)(12,13)\"}\n",
					n, (long)rm[0].rm_so, (long)rm[0].rm_eo,
					(long)rm[1].rm_so, (long)rm[1].rm_eo,
					(long)rm[2].rm_so, (long)rm[2].rm_eo);
				fails++;
			}
			regfree(&r);
		}
	}
	/* Upstream regression/regexec-backref.c: exact patterns/strings. */
	{
		regex_t re;
		regmatch_t rm[2] = { { 0 } };
		if (regcomp(&re, "\\(.\\{1,3\\}\\)\\1", 0) != 0) {
			printf("{\"suite\":\"sinew-bench-f4\",\"probe\":\"backref-regcomp1\"}\n");
			fails++;
		} else {
			int r = regexec(&re, "foo", 2, rm, 0);
			if (r != 0 || rm[1].rm_so != 1 || rm[1].rm_eo != 2) {
				printf("{\"suite\":\"sinew-bench-f4\",\"probe\":\"backref-foo\","
					"\"rc\":%d,\"so\":%d,\"eo\":%d,\"want_so\":1,\"want_eo\":2}\n",
					r, (int)rm[1].rm_so, (int)rm[1].rm_eo);
				fails++;
			}
			regfree(&re);
		}
		if (regcomp(&re, "\\(..*.\\)\\1", 0) != 0) {
			printf("{\"suite\":\"sinew-bench-f4\",\"probe\":\"backref-regcomp2\"}\n");
			fails++;
		} else {
			memset(rm, 0, sizeof rm);
			int r = regexec(&re, "aababa", 2, rm, 0);
			if (r != 0 || rm[1].rm_so != 1 || rm[1].rm_eo != 3) {
				printf("{\"suite\":\"sinew-bench-f4\",\"probe\":\"backref-aababa\","
					"\"rc\":%d,\"so\":%d,\"eo\":%d,\"want_so\":1,\"want_eo\":3}\n",
					r, (int)rm[1].rm_so, (int)rm[1].rm_eo);
				fails++;
			}
			regfree(&re);
		}
	}
}

static const char *subjects[] = {
	"the quick brown fox jumps over the lazy dog 0123456789",
	"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaab",
	"abcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabcabc",
	"foo bar baz qux foo bar baz qux foo bar baz qux end"
};
#define NSUB (sizeof subjects / sizeof subjects[0])

int main(void)
{
	long scale = bench_scale();
	long iters = 20000 * scale;
	double msr[BATCHES], cyc[BATCHES];
	int b;
	long i;
	uint64_t cksum = 1469598103934665603ull;
	const char *verify;
	double mn, md, p95, cmn, cmd, cp95;
	regex_t pats[3];

	verify_regex();
	verify = fails ? "fail" : "pass";

	if (regcomp(&pats[0], "(foo|bar|baz)+", REG_EXTENDED) ||
	    regcomp(&pats[1], "^[a-z]+@[a-z]+\\.[a-z]+$", REG_EXTENDED | REG_NOSUB) ||
	    regcomp(&pats[2], "a*b", 0))
		return 2;
	for (b = 0; b < BATCHES; b++) {
		uint64_t t0 = bench_now_ns();
		uint64_t c0 = bench_cycles();
		uint64_t acc = 0;
		for (i = 0; i < iters; i++) {
			regmatch_t m[2];
			int r;
			/* Zeroed every iteration: the REG_NOSUB pattern must
			 * not read uninitialized match slots into the
			 * checksum (nondeterminism, not a libc issue). */
			memset(m, 0, sizeof m);
			r = regexec(&pats[i % 3], subjects[i % NSUB], 2, m, 0);
			acc = acc * 31 + (uint64_t)(r + m[0].rm_so + m[0].rm_eo);
		}
		uint64_t c1 = bench_cycles();
		uint64_t t1 = bench_now_ns();
		bench_sink_u64(acc);
		cksum = bench_fnv1a(&acc, 8, cksum);
		msr[b] = (double)(t1 - t0) / (double)iters;
		cyc[b] = (double)(c1 - c0) / (double)iters;
	}
	regfree(&pats[0]);
	regfree(&pats[1]);
	regfree(&pats[2]);
	bench_stats(msr, BATCHES, &mn, &md, &p95);
	bench_stats(cyc, BATCHES, &cmn, &cmd, &cp95);
	bench_emit("regex-exec-3pat", BENCH_LINK, verify,
		iters, BATCHES, mn, md, p95,
		1e9 / md, 0.0, cmd, cksum, 0.0,
		"3 compiled patterns x 4 subjects; backref verdicts above, independent");
	return fails ? 1 : 0;
}

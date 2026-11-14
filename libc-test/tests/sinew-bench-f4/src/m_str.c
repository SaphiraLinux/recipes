/* F4 strings: strlen/strcpy/strcmp/strchr/strstr, correctness first.
 *
 * CORRECTNESS (independent references written in this file):
 * - strlen vs a naive byte loop over the same buffer.
 * - strcpy/strcmp/strchr vs naive loops.
 * - strstr (Sinew F8 area) vs naive strstr over fixed haystacks with
 *   1/2/3/4-byte needles, absent needle, empty needle, needle at end.
 * Throughput checksums only prove reproducibility.
 */
#include "bench_common.h"

#ifndef BENCH_LINK
#define BENCH_LINK "dynamic"
#endif

#define BATCHES 21

static int fails;
static uint64_t gck;

static size_t ref_strlen(const char *s)
{
	const char *p = s;
	while (*p)
		p++;
	return (size_t)(p - s);
}

static void *ref_memcpy(void *d, const void *s, size_t n)
{
	unsigned char *dd = d;
	const unsigned char *ss = s;
	size_t i;
	for (i = 0; i < n; i++)
		dd[i] = ss[i];
	return d;
}

static int ref_strcmp(const char *a, const char *b)
{
	while (*a && *a == *b) {
		a++;
		b++;
	}
	return (unsigned char)*a - (unsigned char)*b;
}

static const char *ref_strchr(const char *s, int c)
{
	while (*s) {
		if (*s == (char)c)
			return s;
		s++;
	}
	return c == 0 ? s : 0;
}

static const char *ref_strstr(const char *h, const char *n)
{
	size_t nl = ref_strlen(n);
	const char *p;
	if (!nl)
		return h;
	for (p = h; *p; p++) {
		size_t i;
		for (i = 0; i < nl; i++)
			if (p[i] != n[i])
				break;
		if (i == nl)
			return p;
	}
	return 0;
}

#define HAY "abcXXXXXXdefXXXXdefXXXtail-0123456789-abcdefghijklmnopqrstuvwxyz"

static void verify_str(void)
{
	static const char *needles[] = {
		"e", "bc", "abcXX", "XXXX", "XXXXdef", "XXXXdefXXX", "zz",
		"tail-0123456789-abcdefghijklmnopqrstuvwxyz", ""
	};
	static const char *shorts[] = { "", "a", "ab", "abc" };
	char buf[256];
	size_t i;

	for (i = 0; i < sizeof shorts / sizeof shorts[0]; i++) {
		if (strlen(shorts[i]) != ref_strlen(shorts[i])) {
			printf("{\"suite\":\"sinew-bench-f4\",\"check\":\"strlen\"}\n");
			fails++;
		}
		ref_memcpy(buf, shorts[i], ref_strlen(shorts[i]) + 1);
		if (strcmp(buf, shorts[i]) != 0 || ref_strcmp(buf, shorts[i]) != 0) {
			printf("{\"suite\":\"sinew-bench-f4\",\"check\":\"strcpy\"}\n");
			fails++;
		}
		if ((strchr(shorts[i], 'b') != 0) != (ref_strchr(shorts[i], 'b') != 0)) {
			printf("{\"suite\":\"sinew-bench-f4\",\"check\":\"strchr\"}\n");
			fails++;
		}
	}
	{
		static const char *pairs[][2] = {
			{ "abc", "abc" }, { "abc", "abd" }, { "abd", "abc" },
			{ "", "" }, { "", "a" }, { "a", "" },
			{ "abc", "abcd" }, { "abcd", "abc" }
		};
		for (i = 0; i < sizeof pairs / sizeof pairs[0]; i++) {
			int g = strcmp(pairs[i][0], pairs[i][1]);
			int w = ref_strcmp(pairs[i][0], pairs[i][1]);
			if ((g < 0) != (w < 0) || (g > 0) != (w > 0)) {
				printf("{\"suite\":\"sinew-bench-f4\",\"check\":\"strcmp-sign\"}\n");
				fails++;
			}
		}
	}
	for (i = 0; i < sizeof needles / sizeof needles[0]; i++) {
		const char *g = strstr(HAY, needles[i]);
		const char *w = ref_strstr(HAY, needles[i]);
		if ((g == 0) != (w == 0) || (g && w && g != w)) {
			printf("{\"suite\":\"sinew-bench-f4\",\"check\":\"strstr-%s\"}\n",
				needles[i][0] ? needles[i] : "empty");
			fails++;
		}
	}
}

static void time_str(const char *name, int which, long iters)
{
	double msr[BATCHES], cyc[BATCHES];
	int b;
	long i;
	uint64_t acc = 0;
	double mn, md, p95, cmn, cmd, cp95;
	char buf[256];
	const char *verify = fails ? "fail" : "pass";

	ref_memcpy(buf, HAY, sizeof HAY);
	for (b = 0; b < BATCHES; b++) {
		uint64_t t0 = bench_now_ns();
		uint64_t c0 = bench_cycles();
		for (i = 0; i < iters; i++) {
			if (which == 0)
				acc += strlen(buf);
			else if (which == 1) {
				strcpy(buf, HAY);
				acc += buf[i % 16];
			} else if (which == 2)
				acc += (uint64_t)(strcmp(buf, HAY) == 0);
			else if (which == 3)
				acc += (uint64_t)(strchr(buf, (int)('0' + i % 10)) != 0);
			else
				acc += (uint64_t)(strstr(buf, "XXXXdef") != 0);
			bench_escape(buf);
		}
		uint64_t c1 = bench_cycles();
		uint64_t t1 = bench_now_ns();
		msr[b] = (double)(t1 - t0) / (double)iters;
		cyc[b] = (double)(c1 - c0) / (double)iters;
	}
	bench_sink_u64(acc);
	gck = bench_fnv1a(&acc, 8, gck);
	bench_stats(msr, BATCHES, &mn, &md, &p95);
	bench_stats(cyc, BATCHES, &cmn, &cmd, &cp95);
	bench_emit(name, BENCH_LINK, verify, iters, BATCHES,
		mn, md, p95, 1e9 / md, 0.0, cmd, gck, 0.0,
		"correctness from independent naive refs, see verify_str");
}

int main(void)
{
	long scale = bench_scale();

	verify_str();
	gck = 1469598103934665603ull;
	time_str("strlen-64B", 0, 300000 * scale);
	time_str("strcpy-64B", 1, 200000 * scale);
	time_str("strcmp-eq-64B", 2, 300000 * scale);
	time_str("strchr-hit", 3, 300000 * scale);
	time_str("strstr-7B-needle", 4, 100000 * scale);
	return fails ? 1 : 0;
}

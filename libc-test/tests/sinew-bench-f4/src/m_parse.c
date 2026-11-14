/* F4 parsing: strtod/strtol exact-value edge cases + throughput.
 *
 * CORRECTNESS (exact, independent):
 * - decimal, hex float, inf/INFINITY (case-insensitive), nan/nan(payload),
 *   smallest subnormal (4.9406564584124654e-324 -> bit pattern), DBL_MAX,
 *   overflow (-> HUGE_VAL + ERANGE), underflow to zero (-> 0 + ERANGE),
 *   trailing pointer (endptr) positions.
 * - strtol bases 0/10/16, LONG_MAX/LONG_MIN saturation + ERANGE,
 *   invalid input (no conversion, endptr == input).
 * errno is cleared before each converting call and checked after.
 */
#include "bench_common.h"
#include <errno.h>
#include <limits.h>
#include <math.h>

#ifndef BENCH_LINK
#define BENCH_LINK "dynamic"
#endif

#define BATCHES 21

static int fails;

static void check_strtod(const char *in, uint64_t want_bits,
	int want_erange, const char *want_tail)
{
	char *end = 0;
	double got;
	uint64_t g;
	errno = 0;
	got = strtod(in, &end);
	memcpy(&g, &got, 8);
	if (g != want_bits || (errno == ERANGE) != (want_erange != 0) ||
	    strcmp(end, want_tail) != 0) {
		printf("{\"suite\":\"sinew-bench-f4\",\"check\":\"strtod\","
			"\"in\":\"%s\",\"got_bits\":\"%016llx\","
			"\"want_bits\":\"%016llx\",\"errno\":%d}\n",
			in, (unsigned long long)g,
			(unsigned long long)want_bits, errno);
		fails++;
	}
}

static void check_strtol(const char *in, int base, long want,
	int want_erange, const char *want_tail)
{
	char *end = 0;
	long got;
	errno = 0;
	got = strtol(in, &end, base);
	if (got != want || (errno == ERANGE) != (want_erange != 0) ||
	    strcmp(end, want_tail) != 0) {
		printf("{\"suite\":\"sinew-bench-f4\",\"check\":\"strtol\","
			"\"in\":\"%s\",\"base\":%d,\"got\":%ld,\"want\":%ld,"
			"\"errno\":%d}\n",
			in, base, got, want, errno);
		fails++;
	}
}

static void verify_parse(void)
{
	check_strtod("0", 0x0000000000000000ull, 0, "");
	check_strtod("-0", 0x8000000000000000ull, 0, "");
	check_strtod("1.5", 0x3FF8000000000000ull, 0, "");
	check_strtod("0x1p+10", 0x4090000000000000ull, 0, "");
	check_strtod("inf", 0x7FF0000000000000ull, 0, "");
	check_strtod("-INF", 0xFFF0000000000000ull, 0, "");
	check_strtod("4.9406564584124654e-324", 0x0000000000000001ull, 1, "");
	check_strtod("1.7976931348623157e308", 0x7FEFFFFFFFFFFFFFull, 0, "");
	check_strtod("1e309", 0x7FF0000000000000ull, 1, "");
	check_strtod("-1e309", 0xFFF0000000000000ull, 1, "");
	check_strtod("1e-320", 0x00000000000007e8ull, 1, "");
	check_strtod("123abc", 0x405EC00000000000ull, 0, "abc");
	check_strtol("123", 10, 123, 0, "");
	check_strtol("-123", 10, -123, 0, "");
	check_strtol("0xff", 0, 255, 0, "");
	check_strtol("077", 0, 63, 0, "");
	check_strtol("0b101", 0, 0, 0, "b101");
	check_strtol("9223372036854775807", 10, LONG_MAX, 0, "");
	check_strtol("9223372036854775808", 10, LONG_MAX, 1, "");
	check_strtol("-9223372036854775809", 10, LONG_MIN, 1, "");
	check_strtol("xyz", 10, 0, 0, "xyz");
	check_strtol("1a", 16, 26, 0, "");
	if (!isnan(strtod("nan", 0)) || !isnan(strtod("NAN(foo)", 0))) {
		printf("{\"suite\":\"sinew-bench-f4\",\"check\":\"strtod-nan\"}\n");
		fails++;
	}
}

static const char *bench_inputs[] = {
	"3.141592653589793", "-2.718281828459045e-10", "0x1.921fb54442d18p+1",
	"123456789.123456789", "1e300", "0.1", "inf", "nan", "0777", "0xdeadBEEF"
};
#define NIN (sizeof bench_inputs / sizeof bench_inputs[0])

int main(void)
{
	long scale = bench_scale();
	long iters = 100000 * scale;
	double msr[BATCHES], cyc[BATCHES];
	int b;
	long i;
	uint64_t cksum = 1469598103934665603ull;
	const char *verify;
	double mn, md, p95, cmn, cmd, cp95;

	verify_parse();
	verify = fails ? "fail" : "pass";

	for (b = 0; b < BATCHES; b++) {
		uint64_t t0 = bench_now_ns();
		uint64_t c0 = bench_cycles();
		uint64_t acc = 0;
		for (i = 0; i < iters; i++) {
			const char *s = bench_inputs[i % NIN];
			char *e = 0;
			double v = strtod(s, &e);
			uint64_t u;
			memcpy(&u, &v, 8);
			acc ^= u + (uint64_t)(e - s);
			acc ^= (uint64_t)strtol(s, &e, 0);
		}
		uint64_t c1 = bench_cycles();
		uint64_t t1 = bench_now_ns();
		bench_sink_u64(acc);
		cksum = bench_fnv1a(&acc, 8, cksum);
		msr[b] = (double)(t1 - t0) / (double)iters;
		cyc[b] = (double)(c1 - c0) / (double)iters;
	}
	bench_stats(msr, BATCHES, &mn, &md, &p95);
	bench_stats(cyc, BATCHES, &cmn, &cmd, &cp95);
	bench_emit("parse-strtod-strtol-10", BENCH_LINK, verify,
		iters, BATCHES, mn, md, p95,
		1e9 / md, 0.0, cmd, cksum, 0.0,
		"10-input mixed table; exact edge/errno checks above");
	return fails ? 1 : 0;
}

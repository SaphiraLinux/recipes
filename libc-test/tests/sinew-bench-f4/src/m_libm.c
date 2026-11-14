/* F4 libm: exact-value edge cases + exception flags, then throughput.
 *
 * CORRECTNESS (exact, independent of the timed workload):
 * - exact results: sin(0)=+0, sin(-0)=-0, exp(0)=1, sqrt(4)=2,
 *   pow(2,10)=1024, log(1)=0, floor/ceil/trunc/rint ties, all compared
 *   by bit pattern (memcmp on the double), so signed zero is checked.
 * - NaN: isnan() on sqrt(-1), log(-1), 0.0/0.0-fed sin/cos/exp.
 * - infinities: exp(1000)=+inf, log(0)=-inf, pow(0,-1)=+inf (signbit).
 * - flags (with feclearexcept first): sqrt(-1)->INVALID, log(0)->DIVBYZERO,
 *   exp(1000)->OVERFLOW (+INEXACT allowed, not required), pow(0,-1)->DIVBYZERO.
 * - rounding modes: fesetround DOWNWARD/UPWARD/TONEAREST move rint(0.5)
 *   and nearbyint(2.5) to the exact mandated values; mode restored after.
 * Throughput runs the same functions over a fixed input table; its
 * checksum only proves reproducibility, never correctness.
 */
#include "bench_common.h"
#include <fenv.h>
#include <math.h>

#ifndef BENCH_LINK
#define BENCH_LINK "dynamic"
#endif

#pragma STDC FENV_ACCESS ON

#define BATCHES 31

static int fails;

static void check_bits(const char *name, double got, uint64_t want)
{
	uint64_t g;
	memcpy(&g, &got, 8);
	if (g != want) {
		printf("{\"suite\":\"sinew-bench-f4\",\"check\":\"%s\","
			"\"got_bits\":\"%016llx\",\"want_bits\":\"%016llx\"}\n",
			name, (unsigned long long)g,
			(unsigned long long)want);
		fails++;
	}
}

static void check_flag(const char *name, int got, int want)
{
	if ((got & want) != want) {
		printf("{\"suite\":\"sinew-bench-f4\",\"check\":\"%s\","
			"\"got_flags\":%d,\"want_flags\":%d}\n",
			name, got, want);
		fails++;
	}
}

static void verify_libm(void)
{
	double s;
	int e;

	check_bits("sin(+0)", sin(0.0), 0x0000000000000000ull);
	check_bits("sin(-0)", sin(-0.0), 0x8000000000000000ull);
	check_bits("exp(0)", exp(0.0), 0x3FF0000000000000ull);
	check_bits("sqrt(4)", sqrt(4.0), 0x4000000000000000ull);
	check_bits("pow(2,10)", pow(2.0, 10.0), 0x4090000000000000ull);
	check_bits("log(1)", log(1.0), 0x0000000000000000ull);
	check_bits("floor(0.5)", floor(0.5), 0x0000000000000000ull);
	check_bits("floor(-0.5)", floor(-0.5), 0xBFF0000000000000ull);
	check_bits("ceil(-0.5)", ceil(-0.5), 0x8000000000000000ull);
	check_bits("trunc(-1.9)", trunc(-1.9), 0xBFF0000000000000ull);
	check_bits("rint(2.5)", rint(2.5), 0x4000000000000000ull);
	check_bits("rint(3.5)", rint(3.5), 0x4010000000000000ull);
	check_bits("nearbyint(-0.5)", nearbyint(-0.5), 0x8000000000000000ull);

	s = sqrt(-1.0);
	if (!isnan(s)) {
		printf("{\"suite\":\"sinew-bench-f4\",\"check\":\"sqrt(-1)-isnan\"}\n");
		fails++;
	}
	s = log(-1.0);
	if (!isnan(s)) {
		printf("{\"suite\":\"sinew-bench-f4\",\"check\":\"log(-1)-isnan\"}\n");
		fails++;
	}
	s = exp(1000.0);
	if (!isinf(s) || signbit(s)) {
		printf("{\"suite\":\"sinew-bench-f4\",\"check\":\"exp(1000)-is+inf\"}\n");
		fails++;
	}
	s = log(0.0);
	if (!isinf(s) || !signbit(s)) {
		printf("{\"suite\":\"sinew-bench-f4\",\"check\":\"log(0)-is-inf\"}\n");
		fails++;
	}
	s = pow(0.0, -1.0);
	if (!isinf(s) || signbit(s)) {
		printf("{\"suite\":\"sinew-bench-f4\",\"check\":\"pow(0,-1)-is+inf\"}\n");
		fails++;
	}

	feclearexcept(FE_ALL_EXCEPT);
	s = sqrt(-1.0);
	bench_sink_u64(*(uint64_t *)&s);
	e = fetestexcept(FE_ALL_EXCEPT);
	check_flag("sqrt(-1)-INVALID", e, FE_INVALID);
	feclearexcept(FE_ALL_EXCEPT);
	s = log(0.0);
	bench_sink_u64(*(uint64_t *)&s);
	e = fetestexcept(FE_ALL_EXCEPT);
	check_flag("log(0)-DIVBYZERO", e, FE_DIVBYZERO);
	feclearexcept(FE_ALL_EXCEPT);
	s = exp(1000.0);
	bench_sink_u64(*(uint64_t *)&s);
	e = fetestexcept(FE_ALL_EXCEPT);
	check_flag("exp(1000)-OVERFLOW", e, FE_OVERFLOW);
	feclearexcept(FE_ALL_EXCEPT);
	s = pow(0.0, -1.0);
	bench_sink_u64(*(uint64_t *)&s);
	e = fetestexcept(FE_ALL_EXCEPT);
	check_flag("pow(0,-1)-DIVBYZERO", e, FE_DIVBYZERO);

	fesetround(FE_DOWNWARD);
	s = rint(0.5);
	if (s != 0.0 || signbit(s)) {
		printf("{\"suite\":\"sinew-bench-f4\",\"check\":\"rint-downward\"}\n");
		fails++;
	}
	s = nearbyint(2.5);
	if (s != 2.0) {
		printf("{\"suite\":\"sinew-bench-f4\",\"check\":\"nearbyint-downward\"}\n");
		fails++;
	}
	fesetround(FE_UPWARD);
	s = rint(0.5);
	if (s != 1.0) {
		printf("{\"suite\":\"sinew-bench-f4\",\"check\":\"rint-upward\"}\n");
		fails++;
	}
	s = nearbyint(2.5);
	if (s != 3.0) {
		printf("{\"suite\":\"sinew-bench-f4\",\"check\":\"nearbyint-upward\"}\n");
		fails++;
	}
	fesetround(FE_TONEAREST);
	s = rint(0.5);
	if (s != 0.0) {
		printf("{\"suite\":\"sinew-bench-f4\",\"check\":\"rint-tonearest-restore\"}\n");
		fails++;
	}
}

static double through_inputs[] = {
	0.0, 1.0, -1.0, 0.5, 2.5, 10.0, 100.0,
	1e-300, 1e300, 3.141592653589793, 2.718281828459045
};
#define NIN (sizeof through_inputs / sizeof through_inputs[0])

int main(void)
{
	long scale = bench_scale();
	long iters = 50000 * scale;
	double msr[BATCHES], cyc[BATCHES];
	int b;
	long i;
	uint64_t cksum = 1469598103934665603ull;
	const char *verify;
	double mn, md, p95, cmn, cmd, cp95;

	verify_libm();
	verify = fails ? "fail" : "pass";

	for (b = 0; b < BATCHES; b++) {
		uint64_t t0 = bench_now_ns();
		uint64_t c0 = bench_cycles();
		double acc = 0.0;
		for (i = 0; i < iters; i++) {
			double x = through_inputs[i % NIN];
			acc += sin(x) + cos(x) + exp(x / 100.0) +
				log(1.0 + (x < 0 ? -x : x)) + sqrt(x < 0 ? -x : x) +
				floor(x) + ceil(x) + pow(1.5, x / 100.0);
		}
		uint64_t c1 = bench_cycles();
		uint64_t t1 = bench_now_ns();
		uint64_t ab;
		memcpy(&ab, &acc, 8);
		bench_sink_u64(ab);
		cksum = bench_fnv1a(&ab, 8, cksum);
		msr[b] = (double)(t1 - t0) / (double)(iters * 8);
		cyc[b] = (double)(c1 - c0) / (double)(iters * 8);
	}
	bench_stats(msr, BATCHES, &mn, &md, &p95);
	bench_stats(cyc, BATCHES, &cmn, &cmd, &cp95);
	bench_emit("libm-mixed-8fn", BENCH_LINK, verify,
		iters * 8, BATCHES, mn, md, p95,
		1e9 / md, 0.0, cmd, cksum, 0.0,
		"8 libm calls per iter over 11-value table; flags/edge exact checks above");
	return fails ? 1 : 0;
}

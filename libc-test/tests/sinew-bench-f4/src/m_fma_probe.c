/* F4 fma/fmaf/fmal targeted probes: mirrors the exact failing upstream
 * suite assertions, unweakened. Each probe reports got-vs-want for VALUE
 * and EXCEPTION FLAGS separately, so a partial pass (right value, missing
 * flag) is visible instead of hidden. No musl source is changed by these
 * probes; the prior classification (fma/fmaf INVALID-on-qNaN-addend is
 * test-exceeds-standard per IEEE implementation-defined quiet-NaN;
 * fmal missing UNDERFLOW vs musl's own objective) stands unless new
 * evidence appears. Throughput runs normal values only.
 */
#include "bench_common.h"
#include <fenv.h>
#include <float.h>
#include <math.h>

#ifndef BENCH_LINK
#define BENCH_LINK "dynamic"
#endif

#pragma STDC FENV_ACCESS ON

#define BATCHES 31

static int fails;

static void probe_d(const char *name, int rnd, double x, double y,
	double z, int want_flags)
{
	double r;
	int e;
	fesetround(rnd);
	feclearexcept(FE_ALL_EXCEPT);
	r = fma(x, y, z);
	e = fetestexcept(FE_ALL_EXCEPT);
	if (!isnan(r)) {
		printf("{\"suite\":\"sinew-bench-f4\",\"probe\":\"%s\","
			"\"value\":\"not-nan\"}\n", name);
		fails++;
	}
	if ((e & want_flags) != want_flags) {
		printf("{\"suite\":\"sinew-bench-f4\",\"probe\":\"%s\","
			"\"got_flags\":%d,\"want_flags\":%d}\n",
			name, e & (FE_INVALID | FE_UNDERFLOW | FE_OVERFLOW |
				FE_DIVBYZERO | FE_INEXACT), want_flags);
		fails++;
	}
}

static void probe_f(const char *name, int rnd, float x, float y,
	float z, int want_flags)
{
	float r;
	int e;
	fesetround(rnd);
	feclearexcept(FE_ALL_EXCEPT);
	r = fmaf(x, y, z);
	e = fetestexcept(FE_ALL_EXCEPT);
	if (!isnan(r)) {
		printf("{\"suite\":\"sinew-bench-f4\",\"probe\":\"%s\","
			"\"value\":\"not-nan\"}\n", name);
		fails++;
	}
	if ((e & want_flags) != want_flags) {
		printf("{\"suite\":\"sinew-bench-f4\",\"probe\":\"%s\","
			"\"got_flags\":%d,\"want_flags\":%d}\n",
			name, e & (FE_INVALID | FE_UNDERFLOW | FE_OVERFLOW |
				FE_DIVBYZERO | FE_INEXACT), want_flags);
		fails++;
	}
}

int main(void)
{
	long scale = bench_scale();
	long iters = 200000 * scale;
	double msr[BATCHES], cyc[BATCHES];
	double dnan = nan("");
	float fnan = nanf("");
	int b;
	long i;
	uint64_t cksum = 1469598103934665603ull;
	const char *verify;
	double mn, md, p95, cmn, cmd, cp95;

	/* Upstream special/fma.h:34-37 (RN) + 242-245 (RZ). */
	probe_d("fma-RN-inf-0-nan", FE_TONEAREST, INFINITY, 0.0, dnan, FE_INVALID);
	probe_d("fma-RN-0-inf-nan", FE_TONEAREST, 0.0, INFINITY, dnan, FE_INVALID);
	probe_d("fma-RN--inf-0-nan", FE_TONEAREST, -INFINITY, 0.0, dnan, FE_INVALID);
	probe_d("fma-RN-0--inf-nan", FE_TONEAREST, 0.0, -INFINITY, dnan, FE_INVALID);
	probe_d("fma-RZ-inf-0-nan", FE_TOWARDZERO, INFINITY, 0.0, dnan, FE_INVALID);
	probe_d("fma-RZ-0-inf-nan", FE_TOWARDZERO, 0.0, INFINITY, dnan, FE_INVALID);
	probe_d("fma-RZ--inf-0-nan", FE_TOWARDZERO, -INFINITY, 0.0, dnan, FE_INVALID);
	probe_d("fma-RZ-0--inf-nan", FE_TOWARDZERO, 0.0, -INFINITY, dnan, FE_INVALID);
	/* Upstream special/fmaf.h:34-37 (RN). */
	probe_f("fmaf-RN-inf-0-nan", FE_TONEAREST, INFINITY, 0.0f, fnan, FE_INVALID);
	probe_f("fmaf-RN-0-inf-nan", FE_TONEAREST, 0.0f, INFINITY, fnan, FE_INVALID);
	probe_f("fmaf-RN--inf-0-nan", FE_TONEAREST, -INFINITY, 0.0f, fnan, FE_INVALID);
	probe_f("fmaf-RN-0--inf-nan", FE_TONEAREST, 0.0f, -INFINITY, fnan, FE_INVALID);
#if LDBL_MANT_DIG == 64
	/* Upstream special/fmal.h:46 (RN). Exact value + flags. */
	{
		long double x = -0x1p-10000L;
		long double y = 0x1.0000000000001p-6445L;
		long double z = 0x1p-16382L;
		long double want = 0x1.fffffffffffffffcp-16383L;
		long double r;
		int e;
		fesetround(FE_TONEAREST);
		feclearexcept(FE_ALL_EXCEPT);
		r = fmal(x, y, z);
		e = fetestexcept(FE_ALL_EXCEPT);
		if (r != want) {
			printf("{\"suite\":\"sinew-bench-f4\",\"probe\":\"fmal-value\","
				"\"got\":\"%La\",\"want\":\"%La\"}\n", r, want);
			fails++;
		}
		if ((e & (FE_INEXACT | FE_UNDERFLOW)) != (FE_INEXACT | FE_UNDERFLOW)) {
			printf("{\"suite\":\"sinew-bench-f4\",\"probe\":\"fmal-flags\","
				"\"got_flags\":%d,\"want_flags\":%d}\n",
				e & (FE_INEXACT | FE_UNDERFLOW),
				FE_INEXACT | FE_UNDERFLOW);
			fails++;
		}
	}
#else
	printf("{\"suite\":\"sinew-bench-f4\",\"probe\":\"fmal-skipped\","
		"\"reason\":\"LDBL_MANT_DIG!=64\"}\n");
#endif
	fesetround(FE_TONEAREST);
	verify = fails ? "fail" : "pass";

	for (b = 0; b < BATCHES; b++) {
		uint64_t t0 = bench_now_ns();
		uint64_t c0 = bench_cycles();
		double acc = 0.0;
		for (i = 0; i < iters; i++) {
			double x = 1.0000001 + (double)(i % 97) * 1e-7;
			acc += fma(x, 1.0000002, -1.0000003);
		}
		uint64_t c1 = bench_cycles();
		uint64_t t1 = bench_now_ns();
		uint64_t ab;
		memcpy(&ab, &acc, 8);
		bench_sink_u64(ab);
		cksum = bench_fnv1a(&ab, 8, cksum);
		msr[b] = (double)(t1 - t0) / (double)iters;
		cyc[b] = (double)(c1 - c0) / (double)iters;
	}
	bench_stats(msr, BATCHES, &mn, &md, &p95);
	bench_stats(cyc, BATCHES, &cmn, &cmd, &cp95);
	bench_emit("fma-throughput-normal", BENCH_LINK, verify,
		iters, BATCHES, mn, md, p95,
		1e9 / md, 0.0, cmd, cksum, 0.0,
		"normal values only; edge/flag verdicts above, independent of timing");
	return fails ? 1 : 0;
}

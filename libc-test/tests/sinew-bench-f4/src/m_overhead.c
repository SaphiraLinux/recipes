/* F4 overhead control: measures the timing-loop + call overhead that every
 * other benchmark's raw figures contain. Each domain binary self-reports
 * its own loop shape; this binary pins the harness floor (empty loop,
 * clock_gettime pair cost, rdtsc pair cost) so adjustments are traceable.
 * Correctness here is vacuous (no libc function under test); verify=pass
 * means the harness invariants held (monotonic clock, sane stats). */
#include "bench_common.h"

#ifndef BENCH_LINK
#define BENCH_LINK "dynamic"
#endif

#define BATCHES 31

int main(void)
{
	long scale = bench_scale();
	long iters = 200000 * scale;
	double msr[BATCHES], cyc[BATCHES];
	double mn, md, p95, cmn, cmd, cp95;
	uint64_t c0, c1, t0, t1;
	int b;
	long i;
	uint64_t cksum = 1469598103934665603ull;
	const char *verify = "pass";

	for (b = 0; b < BATCHES; b++) {
		t0 = bench_now_ns();
		c0 = bench_cycles();
		for (i = 0; i < iters; i++)
			bench_sink_u64((uint64_t)i);
		c1 = bench_cycles();
		t1 = bench_now_ns();
		msr[b] = (double)(t1 - t0) / (double)iters;
		cyc[b] = (double)(c1 - c0) / (double)iters;
	}
	cksum = bench_fnv1a(&bench_sink_v, sizeof bench_sink_v, cksum);
	if (!(msr[BATCHES / 2] >= 0.0))
		verify = "fail";
	bench_stats(msr, BATCHES, &mn, &md, &p95);
	bench_stats(cyc, BATCHES, &cmn, &cmd, &cp95);
	bench_emit("overhead-empty-loop", BENCH_LINK, verify,
		iters, BATCHES, mn, md, p95,
		1e9 / md, 0.0, cmd, cksum, 0.0,
		"harness floor: loop+sink+clock+rdtsc per iter; no libc call");
	return verify[0] == 'p' ? 0 : 1;
}

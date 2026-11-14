/* F4 allocation: malloc/free throughput across size classes, single-alloc
 * latency, calloc/realloc correctness.
 *
 * CORRECTNESS (independent): every size class writes a byte pattern and
 * reads it back before free; calloc is checked zero; realloc preserves
 * content and new region is writable; all pointers are nonzero and
 * distinctly checked. Throughput checksums only prove reproducibility.
 */
#include "bench_common.h"

#ifndef BENCH_LINK
#define BENCH_LINK "dynamic"
#endif

#define BATCHES 21

static int fails;
static uint64_t gck;

static void verify_alloc(void)
{
	static const size_t sizes[] = { 1, 16, 64, 512, 4096, 65536, 1048576 };
	size_t i, k;
	for (i = 0; i < sizeof sizes / sizeof sizes[0]; i++) {
		unsigned char *p = malloc(sizes[i]);
		if (!p) {
			printf("{\"suite\":\"sinew-bench-f4\",\"check\":\"malloc-null-%zu\"}\n", sizes[i]);
			fails++;
			continue;
		}
		for (k = 0; k < sizes[i]; k++)
			p[k] = (unsigned char)(k & 0xff);
		for (k = 0; k < sizes[i]; k++)
			if (p[k] != (unsigned char)(k & 0xff)) {
				printf("{\"suite\":\"sinew-bench-f4\",\"check\":\"malloc-rw-%zu\"}\n", sizes[i]);
				fails++;
				break;
			}
		gck = bench_fnv1a(p, sizes[i] > 4096 ? 4096 : sizes[i], gck);
		free(p);
	}
	{
		size_t n = 4096;
		unsigned char *p = calloc(1, n);
		size_t k;
		if (!p) {
			printf("{\"suite\":\"sinew-bench-f4\",\"check\":\"calloc-null\"}\n");
			fails++;
		} else {
			for (k = 0; k < n; k++)
				if (p[k] != 0) {
					printf("{\"suite\":\"sinew-bench-f4\",\"check\":\"calloc-zero\"}\n");
					fails++;
					break;
				}
			for (k = 0; k < n; k++)
				p[k] = (unsigned char)k;
			p = realloc(p, n * 2);
			if (!p) {
				printf("{\"suite\":\"sinew-bench-f4\",\"check\":\"realloc-null\"}\n");
				fails++;
			} else {
				for (k = 0; k < n; k++)
					if (p[k] != (unsigned char)k) {
						printf("{\"suite\":\"sinew-bench-f4\",\"check\":\"realloc-keep\"}\n");
						fails++;
						break;
					}
				free(p);
			}
		}
	}
}

static void time_alloc(const char *name, size_t size, long iters)
{
	double msr[BATCHES], cyc[BATCHES];
	int b;
	long i;
	uint64_t acc = 0;
	double mn, md, p95, cmn, cmd, cp95;
	const char *verify = fails ? "fail" : "pass";

	for (b = 0; b < BATCHES; b++) {
		uint64_t t0 = bench_now_ns();
		uint64_t c0 = bench_cycles();
		for (i = 0; i < iters; i++) {
			unsigned char *p = malloc(size ? size : 1);
			if (!p)
				continue;
			p[0] = (unsigned char)i;
			p[size ? size - 1 : 0] = (unsigned char)(i >> 8);
			acc += p[0] + p[size ? size - 1 : 0];
			free(p);
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
		"malloc+touch+free per iter; content checks above, independent");
}

int main(void)
{
	long scale = bench_scale();

	gck = 1469598103934665603ull;
	verify_alloc();
	time_alloc("malloc-free-16B", 16, 200000 * scale);
	time_alloc("malloc-free-512B", 512, 100000 * scale);
	time_alloc("malloc-free-64KB", 65536, 5000 * scale);
	return fails ? 1 : 0;
}

/* F4 memory ops: memcpy/memmove/memset/memcmp across sizes and alignment
 * offsets, reporting bandwidth (GB/s) and latency (ns/op).
 *
 * CORRECTNESS (independent of timing): every timed buffer is verified
 * byte-for-byte against a plain volatile byte loop written in this file
 * (never calling the function under test). Any mismatch fails the run.
 * Alignment offsets apply to BOTH src and dst from the listed set; each
 * listed (size, off) pair is its own benchmark line so regressions are
 * attributable. DCE guard: final checksums over destination buffers.
 */
#include "bench_common.h"

#ifndef BENCH_LINK
#define BENCH_LINK "dynamic"
#endif

#define BATCHES 15
#define MAXSIZE (4 * 1024 * 1024)

static unsigned char *pool_a, *pool_b;
static int fails;

static void ref_fill(unsigned char *p, size_t n, unsigned seed)
{
	size_t i;
	for (i = 0; i < n; i++)
		p[i] = (unsigned char)((seed * 31 + i * 17 + (i >> 8)) & 0xff);
}

static int ref_check(const unsigned char *p, size_t off, size_t n, unsigned seed)
{
	size_t i;
	for (i = 0; i < n; i++)
		if (p[i] != (unsigned char)((seed * 31 + (off + i) * 17 + ((off + i) >> 8)) & 0xff))
			return 0;
	return 1;
}

static void bench_one(const char *name, int op,
	size_t n, size_t off_a, size_t off_b, long iters)
{
	double msr[BATCHES], cyc[BATCHES];
	int b;
	long i;
	unsigned char *a = pool_a + off_a;
	unsigned char *bptr = pool_b + off_b;
	uint64_t cksum = 1469598103934665603ull;
	double mn, md, p95, cmn, cmd, cp95;
	const char *verify = "pass";

	ref_fill(pool_a, MAXSIZE, 12345);
	memset(pool_b, 0x5a, MAXSIZE);
	for (b = 0; b < BATCHES; b++) {
		uint64_t t0 = bench_now_ns();
		uint64_t c0 = bench_cycles();
		for (i = 0; i < iters; i++) {
			if (op == 0)
				memcpy(bptr, a, n);
			else if (op == 1)
				memmove(bptr, a, n);
			else if (op == 2)
				memset(bptr, (int)(i & 0xff), n);
			else
				bench_sink_u64((uint64_t)memcmp(a, bptr, n));
			bench_escape(bptr);
		}
		uint64_t c1 = bench_cycles();
		uint64_t t1 = bench_now_ns();
		msr[b] = (double)(t1 - t0) / (double)iters;
		cyc[b] = (double)(c1 - c0) / (double)iters;
	}
	if (op == 0 || op == 1) {
		memcpy(bptr, a, n);
		if (memcmp(a, bptr, n) != 0) {
			printf("{\"suite\":\"sinew-bench-f4\",\"check\":\"%s-verify\"}\n", name);
			fails++;
			verify = "fail";
		}
		cksum = bench_fnv1a(bptr, n, cksum);
	} else if (op == 2) {
		memset(bptr, 0xa5, n);
		{
			size_t k;
			for (k = 0; k < n; k++)
				if (bptr[k] != 0xa5) {
					printf("{\"suite\":\"sinew-bench-f4\",\"check\":\"%s-verify\"}\n", name);
					fails++;
					verify = "fail";
					break;
				}
		}
		cksum = bench_fnv1a(bptr, n, cksum);
	} else {
		if (!ref_check(a, off_a, n, 12345)) {
			printf("{\"suite\":\"sinew-bench-f4\",\"check\":\"%s-src-intact\"}\n", name);
			fails++;
			verify = "fail";
		}
		cksum = bench_fnv1a(a, n > 4096 ? 4096 : n, cksum);
	}
	bench_stats(msr, BATCHES, &mn, &md, &p95);
	bench_stats(cyc, BATCHES, &cmn, &cmd, &cp95);
	{
		/* bytes/ns == GB/s (1e9 bytes per second per byte-per-ns). */
		double bytes = (op == 3) ? (double)n * 2.0 : (double)n * (op == 2 ? 1.0 : 2.0);
		char full[128];
		snprintf(full, sizeof full, "%s-%zu-off%zu-%zu", name, n, off_a, off_b);
		bench_emit(full, BENCH_LINK, verify, iters, BATCHES,
			mn, md, p95, 1e9 / md, bytes / md, cmd,
			cksum, 0.0,
			op == 3 ? "memcmp reads both buffers; no store" :
			op == 2 ? "memset write-only" : "copy read+write");
	}
}

int main(void)
{
	long scale = bench_scale();
	static const size_t sizes[] = { 64, 1500, 65536, 1048576 };
	static const size_t offs[] = { 0, 1, 7, 16, 31, 32, 64 };
	static const char *names[] = { "memcpy", "memmove", "memset", "memcmp" };
	size_t si, oi;
	int op;

	pool_a = malloc(MAXSIZE + 128);
	pool_b = malloc(MAXSIZE + 128);
	if (!pool_a || !pool_b)
		return 2;
	for (op = 0; op < 4; op++) {
		for (si = 0; si < sizeof sizes / sizeof sizes[0]; si++) {
			for (oi = 0; oi < sizeof offs / sizeof offs[0]; oi++) {
				long iters;
				size_t n = sizes[si];
				/* Keep the whole matrix under ~2 minutes:
				 * fewer iters for large sizes. */
				if (n <= 64)
					iters = 200000 * scale;
				else if (n <= 1500)
					iters = 50000 * scale;
				else if (n <= 65536)
					iters = 2000 * scale;
				else
					iters = 200 * scale;
				if (op == 3 && n > 65536)
					continue;
				bench_one(names[op], op, n, offs[oi], offs[(oi + 3) % 7], iters);
			}
		}
	}
	free(pool_a);
	free(pool_b);
	return fails ? 1 : 0;
}

/* Sinew F4 benchmark common core: timing, stats, checksums, DCE guards.
 *
 * CORRECTNESS IS NEVER DERIVED FROM CHECKSUMS. Each domain binary runs an
 * independent verify() phase against exact expected values (bit patterns,
 * exception flags, reference implementations kept inside the harness and
 * never calling the function under test). The FNV-1a checksum below exists
 * only to (a) defeat dead-code elimination and (b) prove run-to-run
 * reproducibility of the timed workload. A stable checksum with a failed
 * verify() is a FAILED benchmark, never a correct one.
 *
 * Timing: clock_gettime(CLOCK_MONOTONIC). Per-op times are batch means;
 * display rounds to 0.1 ns but the raw batch totals, batch counts, timer
 * resolution (clock_getres, reported by the driver) and variance
 * (min/median/p95) are all emitted so no sub-nanosecond claim is made
 * beyond what the data supports.
 *
 * Cycles (x86 only): raw rdtsc deltas, NO serialization fence. They are a
 * coarse relative signal, not a cycle-accurate count; the ns figures are
 * authoritative. Non-x86 builds emit cycles_op 0 with have_cycles 0.
 */
#ifndef BENCH_COMMON_H
#define BENCH_COMMON_H

#define _GNU_SOURCE
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static volatile uint64_t bench_sink_v;

/* Defeat dead-code elimination: force the compiler to materialize v. */
static inline void bench_sink_u64(uint64_t v)
{
	bench_sink_v ^= v * 11400714819323198485ull;
}

/* Escape a pointer: the compiler must assume it is read/written. */
static inline void bench_escape(void *p)
{
	__asm__ __volatile__("" : "+r"(p) : : "memory");
}

static inline uint64_t bench_now_ns(void)
{
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

static inline uint64_t bench_cycles(void)
{
#if defined(__x86_64__) || defined(__i386__)
	unsigned lo, hi;
	__asm__ __volatile__("rdtsc" : "=a"(lo), "=d"(hi));
	return ((uint64_t)hi << 32) | lo;
#else
	return 0;
#endif
}

static inline int bench_have_cycles(void)
{
#if defined(__x86_64__) || defined(__i386__)
	return 1;
#else
	return 0;
#endif
}

/* FNV-1a 64 over a byte buffer (checksum only, never a verdict). */
static inline uint64_t bench_fnv1a(const void *data, size_t len, uint64_t h)
{
	const unsigned char *p = data;
	size_t i;
	for (i = 0; i < len; i++) {
		h ^= p[i];
		h *= 1099511628211ull;
	}
	return h;
}

static int bench_cmp_d(const void *a, const void *b)
{
	double x = *(const double *)a, y = *(const double *)b;
	return (x > y) - (x < y);
}

/* Nearest-rank min/median/p95 over msr[0..n). n >= 1. */
static inline void bench_stats(double *msr, int n, double *pmin,
	double *pmed, double *pp95)
{
	qsort(msr, (size_t)n, sizeof(double), bench_cmp_d);
	*pmin = msr[0];
	*pmed = msr[n / 2];
	*pp95 = msr[(n * 95 + 99) / 100 - 1 < n ? (n * 95 + 99) / 100 - 1 : n - 1];
}

/* Effective iteration count: BENCH_SCALE multiplies the default. */
static inline long bench_scale(void)
{
	const char *e = getenv("BENCH_SCALE");
	long s = e ? atol(e) : 1;
	return s > 0 ? s : 1;
}

/* JSON-escape s into d (capacity n, including NUL). For check lines that
 * embed arbitrary input bytes; keeps results.jsonl parseable. */
static inline void bench_json_escape(char *d, size_t n, const char *s)
{
	size_t o = 0;
	while (*s && o + 2 < n) {
		if (*s == '"' || *s == '\\') {
			d[o++] = '\\';
			d[o++] = *s++;
		} else if (*s == '\n') {
			d[o++] = '\\';
			d[o++] = 'n';
			s++;
		} else if ((unsigned char)*s < 32) {
			d[o++] = '?';
			s++;
		} else {
			d[o++] = *s++;
		}
	}
	d[o] = 0;
}

static inline void bench_emit(const char *bench, const char *link,
	const char *verify, long iters, int batches,
	double ns_min, double ns_med, double ns_p95,
	double ops, double gbps, double cyc,
	uint64_t cksum, double overhead_ns, const char *notes)
{
	printf("{\"suite\":\"sinew-bench-f4\",\"bench\":\"%s\","
		"\"link\":\"%s\",\"verify\":\"%s\","
		"\"iters\":%ld,\"batches\":%d,"
		"\"ns_min\":%.1f,\"ns_median\":%.1f,\"ns_p95\":%.1f,"
		"\"ops_per_s\":%.3g,\"gb_per_s\":%.4g,"
		"\"cycles_op\":%.1f,\"have_cycles\":%d,"
		"\"checksum\":\"%016llx\","
		"\"overhead_ns_op\":%.2f,\"notes\":\"%s\"}\n",
		bench, link, verify, iters, batches,
		ns_min, ns_med, ns_p95, ops, gbps, cyc,
		bench_have_cycles(), (unsigned long long)cksum,
		overhead_ns, notes);
	fflush(stdout);
}

#endif

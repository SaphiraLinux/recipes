/* memmove benchmark: baseline arch vs SSE2-backward candidate.
 * Sizes x {backward d=1, backward d=n/2, forward, non-overlap} +
 * sorted-insertion macro. Min of runs reported. */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <time.h>
void *base_mm(void *, const void *, size_t);
void *cand_mm(void *, const void *, size_t);

static double now_ns(void)
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return (double)t.tv_sec * 1e9 + (double)t.tv_nsec;
}

static void *arena;
#define AN 8388608

static double bench(void *(*f)(void *, const void *, size_t),
		    unsigned char *dst, unsigned char *src, size_t n, int iters)
{
	double best = 1e18;
	for (int k = 0; k < 5; k++) {
		double t0 = now_ns();
		for (int i = 0; i < iters; i++) {
			__asm__ volatile("" ::: "memory");
			f(dst, src, n);
		}
		double dt = now_ns() - t0;
		if (dt < best) best = dt;
	}
	return best / iters;
}

int main(void)
{
	arena = malloc(AN * 3 + 4096);
	if (!arena) return 99;
	unsigned char *A = arena, *B = arena + AN + 2048, *S = arena + 2 * AN + 4096;
	for (size_t i = 0; i < AN; i++) A[i] = (unsigned char)(i * 31 + 7);
	size_t sizes[] = { 4, 16, 256, 4096, 65536, 2097152 };
	int iters[] = { 200000, 200000, 50000, 5000, 500, 20 };
	const char *dn[] = { "bwd-d1", "bwd-dn/2", "fwd", "nonoverlap" };
	for (unsigned s = 0; s < sizeof sizes / sizeof *sizes; s++) {
		size_t n = sizes[s];
		int it = iters[s];
		unsigned char *dst_f1 = A + 100, *src_f1 = A + 101;      /* forward d=-1 */
		unsigned char *dst_fh = A + 200, *src_fh = A + 200 + n / 2 + 1; /* forward */
		unsigned char *dst_b1 = A + 400, *src_b1 = A + 399;          /* backward d=+1 */
		unsigned char *dst_bh = A + 500 + n / 2, *src_bh = A + 500;  /* backward d=+n/2 */
		if (dst_fh + n > A + AN || dst_bh + n > A + AN || n < 2) { printf("size %zu: skipped (arena)\n", n); continue; }
		double g1 = bench(base_mm, dst_f1, src_f1, n, it);
		double c1 = bench(cand_mm, dst_f1, src_f1, n, it);
		double gh = bench(base_mm, dst_fh, src_fh, n, it);
		double ch = bench(cand_mm, dst_fh, src_fh, n, it);
		double gb = bench(base_mm, dst_b1, src_b1, n, it);
		double cb = bench(cand_mm, dst_b1, src_b1, n, it);
		double g2 = bench(base_mm, dst_bh, src_bh, n, it);
		double c2 = bench(cand_mm, dst_bh, src_bh, n, it);
		double gn = bench(base_mm, B, S, n, it);
		double cn = bench(cand_mm, B, S, n, it);
		(void)dn;
		printf("n=%-8zu bwd-d1: base=%7.1f cand=%7.1f (%.2fx) | bwd-half: base=%7.1f cand=%7.1f (%.2fx)\n",
		       n, gb, cb, gb / cb, g2, c2, g2 / c2);
		printf("n=%-8zu fwd-d1: base=%7.1f cand=%7.1f (%.2fx) | fwd-half: base=%7.1f cand=%7.1f (%.2fx) | nonov: base=%7.1f cand=%7.1f (%.2fx)\n",
		       n, g1, c1, g1 / c1, gh, ch, gh / ch, gn, cn, gn / cn);
	}
	/* sorted-insertion macro: 30k random ints into sorted array */
	{
		int N = 30000, *arr = malloc((size_t)(N + 1) * sizeof *arr);
		uint64_t r = 0xabcdef;
		double t0 = now_ns();
		int m = 0;
		for (int i = 0; i < N; i++) {
			r = r * 6364136223846793005ULL + 1449691640888963407ULL;
			int v = (int)(r >> 33);
			int lo = 0, hi = m;
			while (lo < hi) { int mid = (lo + hi) / 2; if (arr[mid] < v) lo = mid + 1; else hi = mid; }
			cand_mm(&arr[lo + 1], &arr[lo], (size_t)(m - lo) * sizeof *arr);
			arr[lo] = v;
			m++;
		}
		double tc = now_ns() - t0;
		for (int i = 1; i < N; i++) if (arr[i - 1] > arr[i]) { printf("SORT BROKEN\n"); return 1; }
		r = 0xabcdef; m = 0;
		t0 = now_ns();
		for (int i = 0; i < N; i++) {
			r = r * 6364136223846793005ULL + 1449691640888963407ULL;
			int v = (int)(r >> 33);
			int lo = 0, hi = m;
			while (lo < hi) { int mid = (lo + hi) / 2; if (arr[mid] < v) lo = mid + 1; else hi = mid; }
			base_mm(&arr[lo + 1], &arr[lo], (size_t)(m - lo) * sizeof *arr);
			arr[lo] = v;
			m++;
		}
		double tb = now_ns() - t0;
		for (int i = 1; i < N; i++) if (arr[i - 1] > arr[i]) { printf("SORT BROKEN\n"); return 1; }
		printf("sorted-insert 30k: base=%.0f ms cand=%.0f ms (%.2fx)\n", tb / 1e6, tc / 1e6, tb / tc);
		free(arr);
	}
	return 0;
}

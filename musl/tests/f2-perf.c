/* F2 perf: mixed-input throughput, generic (live r7) vs suppress-imm. */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>
#include <math.h>
static double c_floor(double x)
{ double y; __asm__ volatile("roundsd $9, %1, %0" : "=x"(y) : "x"(x)); return y; }
static double c_nearby(double x)
{ double y; __asm__ volatile("roundsd $12, %1, %0" : "=x"(y) : "x"(x)); return y; }
int main(void)
{
	int n = 20000000;
	double *v = malloc((size_t)n * sizeof *v),
	       *w = malloc((size_t)n * sizeof *v);
	uint64_t s = 0x123456789abcdefULL;
	for (int i = 0; i < n; i++) {
		s = s * 6364136223846793005ULL + 1449691640888963407ULL;
		uint64_t u = s & 0x7fffffffffffffffULL;
		if (((u >> 52) & 0x7ff) == 0x7ff) u ^= 0x0008000000000000ULL;
		memcpy(&v[i], &u, 8);
	}
	struct timespec t0, t1, t2, t3;
	volatile double c = 0;
	clock_gettime(CLOCK_MONOTONIC, &t0);
	for (int i = 0; i < n; i++) w[i] = c_floor(v[i]);
	clock_gettime(CLOCK_MONOTONIC, &t1);
	for (int i = 0; i < n; i++) w[i] = floor(v[i]);
	clock_gettime(CLOCK_MONOTONIC, &t2);
	for (int i = 0; i < n; i++) w[i] = c_nearby(v[i]);
	clock_gettime(CLOCK_MONOTONIC, &t3);
	for (int i = 0; i < n; i += 4096) c += w[i];
	double a = (t1.tv_sec - t0.tv_sec) * 1e9 + (t1.tv_nsec - t0.tv_nsec);
	double b = (t2.tv_sec - t1.tv_sec) * 1e9 + (t2.tv_nsec - t1.tv_nsec);
	double d = (t3.tv_sec - t2.tv_sec) * 1e9 + (t3.tv_nsec - t2.tv_nsec);
	struct timespec t4, t5;
	clock_gettime(CLOCK_MONOTONIC, &t4);
	for (int i = 0; i < n; i++) w[i] = nearbyint(v[i]);
	clock_gettime(CLOCK_MONOTONIC, &t5);
	for (int i = 0; i < n; i += 4096) c += w[i];
	double e = (t5.tv_sec - t4.tv_sec) * 1e9 + (t5.tv_nsec - t4.tv_nsec);
	printf("floor: cand=%.1f generic=%.1f ns (ratio %.2f); nearby: cand=%.1f generic=%.1f ns (ratio %.2f) chk=%f\n",
	       a / n, b / n, b / a, d / n, e / n, e / d, c);
	free(v); free(w);
	return 0;
}

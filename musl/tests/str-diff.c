/* Sketch differential + bench: sk_* vs live libc, correctness first. */
#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>
#include <sys/mman.h>
#include <sys/wait.h>
#include <unistd.h>
int sk_strncmp(const char *, const char *, size_t);
int sk_memcmp(const void *, const void *, size_t);
void *sk_memchr(const void *, int, size_t);

static uint64_t rng = 0x9e3779b97f4a7c15ULL;
static unsigned rnd(void)
{ rng = rng * 6364136223846793005ULL + 1449691640888963407ULL; return (unsigned)(rng >> 33); }

static long fails = 0, checked = 0;
static void chk(int ok, const char *what, size_t n, unsigned extra)
{
	checked++;
	if (!ok) { fails++; if (fails < 15) printf("DIFF %s n=%zu x=%u\n", what, n, extra); }
}

int main(void)
{
	/* correctness: alignments x NUL/mismatch positions x lengths */
	for (int trial = 0; trial < 40000; trial++) {
		size_t n = rnd() % 300;
		unsigned ao = rnd() % 16, bo = rnd() % 16;
		static char A[1024], B[1024], C[1024], D[1024];
		for (size_t i = 0; i < n + 64; i++) {
			unsigned char v = (unsigned char)rnd();
			A[i] = B[i] = C[i] = D[i] = (char)v;
		}
		/* sprinkle NULs and mismatches */
		if (trial % 3 == 0 && n > 0) { size_t p = rnd() % n; A[p] = B[p] = 0; }
		if (trial % 3 == 1 && n > 0) { size_t p = rnd() % n; B[p] ^= 1; D[p] ^= 2; }
		if (trial % 5 == 0) { size_t p = n > 0 ? rnd() % n : 0; C[p] = 0; }
		char *a = A + ao, *b = B + bo, *c = C + ao, *d = D + bo;
		int r1 = strncmp(a, b, n), r2 = sk_strncmp(a, b, n);
		chk((r1 == 0 && r2 == 0) || (r1 < 0 && r2 < 0) || (r1 > 0 && r2 > 0), "strncmp", n, ao * 32 + bo);
		int m1 = memcmp(c, d, n), m2 = sk_memcmp(c, d, n);
		chk((m1 == 0 && m2 == 0) || (m1 < 0 && m2 < 0) || (m1 > 0 && m2 > 0), "memcmp", n, ao * 32 + bo);
		int ch = rnd() % 256;
		size_t lim = n + (rnd() % 32);
		void *e1 = memchr(a, ch, lim < 560 ? lim : 560);
		void *e2 = sk_memchr(a, ch, lim < 560 ? lim : 560);
		chk(e1 == e2 || (e1 && e2 && *(char *)e1 == ch && *(char *)e2 == ch && (char *)e1 - a == (char *)e2 - a), "memchr", lim, ch);
	}
	/* page-boundary: strings ending exactly at page end, child-isolated */
	for (int t = 0; t < 300; t++) {
		pid_t p = fork();
		if (p == 0) {
			size_t pagesz = 4096;
			unsigned char *m = mmap(NULL, 3 * pagesz, PROT_NONE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
			if (m == MAP_FAILED) _exit(7);
			mprotect(m, pagesz, PROT_READ | PROT_WRITE);
			mprotect(m + 2 * pagesz, pagesz, PROT_READ | PROT_WRITE);
			size_t len = 1 + rnd() % 64;
			unsigned off = rnd() % 32;
			unsigned char *s = m + pagesz - len - off;
			if (s < m || s + len + 16 > m + 2 * pagesz) _exit(3);
			for (size_t i = 0; i < len + 16; i++) s[i] = (unsigned char)(i + 1);
			int ch = (t % 2) ? s[len / 2] : 0x7f;
			void *e1 = memchr(s, ch, len);
			void *e2 = sk_memchr(s, ch, len);
			int ok = (e1 == e2);
			char *a = (char *)s, *b = (char *)s;
			if (t % 3 == 0 && len > 2) b[0] = 0;
			int r1 = strncmp(a, b, len), r2 = sk_strncmp(a, b, len);
			ok = ok && ((r1 == 0 && r2 == 0) || (r1 < 0 && r2 < 0) || (r1 > 0 && r2 > 0));
			_exit(ok ? 0 : 5);
		}
		int st = 0; waitpid(p, &st, 0); checked++;
		if (!WIFEXITED(st) || WEXITSTATUS(st) == 3) { checked--; continue; }
		if (!WIFEXITED(st) || WEXITSTATUS(st) != 0) { fails++; if (fails < 10) printf("GUARD-FAIL st=%d\n", st); }
	}
	printf("STR-DIFF checked=%ld fails=%ld\n", checked, fails);
	if (fails) return 1;
	/* benchmarks, same shapes as baseline */
	static char h[65536 + 64], h2[65536 + 64];
	for (int i = 0; i < 65536 + 64; i++) { h[i] = (char)(33 + (i % 90)); h2[i] = h[i]; }
	h[65535] = 0; h2[65535] = 0;
	struct { const char *n; int it; } cfg[] = {
		{ "eq16", 200000 }, { "eq64", 200000 }, { "eq256", 100000 }, { "eq4k", 20000 },
	};
	(void)cfg;
#define BOTH(label, iters, gen_call, sk_call) do { \
		struct timespec t0, t1; volatile int sink = 0; double bg = 1e18, cg = 1e18; \
		for (int k = 0; k < 5; k++) { \
			clock_gettime(CLOCK_MONOTONIC, &t0); \
			for (int i = 0; i < iters; i++) { sink += (gen_call); } \
			struct timespec t2; clock_gettime(CLOCK_MONOTONIC, &t2); \
			double dt = (t2.tv_sec - t0.tv_sec) * 1e9 + (t2.tv_nsec - t0.tv_nsec); \
			if (dt < bg) bg = dt; \
		} \
		for (int k = 0; k < 5; k++) { \
			clock_gettime(CLOCK_MONOTONIC, &t0); \
			for (int i = 0; i < iters; i++) { sink += (sk_call); } \
			struct timespec t2; clock_gettime(CLOCK_MONOTONIC, &t2); \
			double dt = (t2.tv_sec - t0.tv_sec) * 1e9 + (t2.tv_nsec - t0.tv_nsec); \
			if (dt < cg) cg = dt; \
		} \
		printf("%-26s gen=%7.1f sk=%7.1f (%.2fx)\n", label, bg / iters, cg / iters, bg / cg); \
	} while (0)
	BOTH("strncmp eq16", 200000, strncmp(h, h2, 16), sk_strncmp(h, h2, 16));
	BOTH("strncmp eq64", 200000, strncmp(h, h2, 64), sk_strncmp(h, h2, 64));
	BOTH("strncmp eq256", 100000, strncmp(h, h2, 256), sk_strncmp(h, h2, 256));
	BOTH("strncmp eq4k", 20000, strncmp(h, h2, 4096), sk_strncmp(h, h2, 4096));
	BOTH("memcmp eq64", 200000, memcmp(h, h2, 64), sk_memcmp(h, h2, 64));
	BOTH("memcmp eq4k", 20000, memcmp(h, h2, 4096), sk_memcmp(h, h2, 4096));
	BOTH("memchr absent64", 200000, (memchr(h, 127, 64) != 0), (sk_memchr(h, 127, 64) != 0));
	BOTH("memchr absent4k", 20000, (memchr(h, 127, 4096) != 0), (sk_memchr(h, 127, 4096) != 0));
	BOTH("memchr absent64k", 2000, (memchr(h, 127, 65536) != 0), (sk_memchr(h, 127, 65536) != 0));
	return 0;
}

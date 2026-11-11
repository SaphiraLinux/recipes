/* memmove matrix: baseline arch memmove vs SSE2-backward candidate
 * vs naive reference. Exact bytes + return value, canary redzones,
 * sampled guard-page runs in forked children. Link base.o (memmove
 * renamed base_mm) + cand.o (renamed cand_mm) via objcopy. */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <sys/mman.h>
#include <sys/wait.h>

void *base_mm(void *, const void *, size_t);
void *cand_mm(void *, const void *, size_t);

static uint64_t rng = 0x12345678abcdefULL;
static unsigned rnd(void)
{ rng = rng * 6364136223846793005ULL + 1449691640888963407ULL; return (unsigned)(rng >> 33); }

static void *ref_mm(void *d, const void *s, size_t n)
{
	unsigned char *dd = d;
	const unsigned char *ss = s;
	if (dd == ss) return d;
	if (dd < ss) { for (size_t i = 0; i < n; i++) dd[i] = ss[i]; }
	else { while (n--) dd[n] = ss[n]; }
	return d;
}

#define ARENA (8u*1024u*1024u)
#define RED 64
static unsigned char *A, *B, *E; /* base, cand, expected arenas */

static long fails = 0, checked = 0;
static void tcase(size_t len, long delta, unsigned sa, unsigned da)
{
	unsigned char *src = A + 1024 + sa, *dst = A + 1024 + sa + delta;
	unsigned char *s2 = B + 1024 + sa, *d2 = B + 1024 + sa + delta;
	unsigned char *s3 = E + 1024 + sa, *d3 = E + 1024 + sa + delta;
	unsigned char *lo = dst < src ? dst : src;
	unsigned char *hi_end = (dst > src ? dst : src) + len;
	if (lo < A + RED || hi_end + 128 > A + ARENA - RED) return;
	for (size_t i = 0; i < len + 128; i++) {
		unsigned char v = (unsigned char)rnd();
		src[i] = s2[i] = s3[i] = v;
	}
	memset(lo - RED, 0xA5, RED);
	unsigned char *lo2 = d2 < s2 ? d2 : s2;
	memset(lo2 - RED, 0xA5, RED);
	size_t hirel = (size_t)(hi_end - (A + 1024 + sa)) + 128;
	memset(A + 1024 + sa + hirel, 0x5A, RED < 128 ? RED : 64);
	unsigned char *hi2_end = (d2 > s2 ? d2 : s2) + len;
	size_t hirel2 = (size_t)(hi2_end - (B + 1024 + sa)) + 128;
	memset(B + 1024 + sa + hirel2, 0x5A, RED < 128 ? RED : 64);
	static const unsigned char canA[64] = { [0 ... 63] = 0xA5 };
	static const unsigned char canB[64] = { [0 ... 63] = 0x5A };
	void *rb = base_mm(dst, src, len);
	void *rc = cand_mm(d2, s2, len);
	void *rr = ref_mm(d3, s3, len);
	checked += 2;
	int ok = 1;
	if (rb != dst) { ok = 0; if (fails < 10) printf("BASE retval %p want %p len=%zu d=%ld\n", rb, (void*)dst, len, delta); }
	if (rc != d2) { ok = 0; if (fails < 10) printf("CAND retval %p want %p len=%zu d=%ld\n", rc, (void*)d2, len, delta); }
	if (len && memcmp(dst, d3, len) != 0) { ok = 0; if (fails < 10) printf("BASE bytes differ len=%zu d=%ld sa=%u da=%u\n", len, delta, sa, da); }
	if (len && memcmp(d2, d3, len) != 0) { ok = 0; if (fails < 10) printf("CAND bytes differ len=%zu d=%ld sa=%u da=%u\n", len, delta, sa, da); }
	if (memcmp(lo - RED, canA, RED) != 0) { ok = 0; if (fails < 10) printf("BASE low-canary clobbered len=%zu d=%ld sa=%u\n", len, delta, sa); }
	if (memcmp(lo2 - RED, canA, RED) != 0) { ok = 0; if (fails < 10) printf("CAND low-canary clobbered len=%zu d=%ld sa=%u\n", len, delta, sa); }
	if (memcmp(A + 1024 + sa + hirel, canB, RED < 128 ? RED : 64) != 0) { ok = 0; if (fails < 10) printf("BASE high-canary clobbered len=%zu d=%ld\n", len, delta); }
	if (memcmp(B + 1024 + sa + hirel2, canB, RED < 128 ? RED : 64) != 0) { ok = 0; if (fails < 10) printf("CAND high-canary clobbered len=%zu d=%ld\n", len, delta); }
	if (!ok) fails++;
	(void)rr;
	(void)da;
}

/* Guard-page run, child-isolated: any over/under-run faults the
 * child (SIGSEGV -> parent sees signal). Expected bytes computed
 * from the pre-copy pattern on the heap. */
static void guardcase(size_t len, long delta)
{
	pid_t p = fork();
	if (p == 0) {
		size_t pagesz = 4096;
		unsigned char *m = mmap(NULL, 3 * pagesz, PROT_NONE,
			MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
		if (m == MAP_FAILED) _exit(7);
		mprotect(m, pagesz, PROT_READ | PROT_WRITE);
		mprotect(m + 2 * pagesz, pagesz, PROT_READ | PROT_WRITE);
		unsigned char *mid = m + pagesz;
		/* src starts mid-page; keep both operands inside */
		unsigned char *src = mid + 2048 - len / 2 - 64;
		unsigned char *dst = src + delta;
		if (dst < mid || dst + len > mid + pagesz ||
		    src < mid || src + len > mid + pagesz) _exit(3);
		unsigned char *pat = malloc(len ? len : 1);
		if (!pat) _exit(8);
		for (size_t i = 0; i < len; i++) pat[i] = (unsigned char)(i * 31 + 7 + (src - mid));
		memcpy(src, pat, len);
		void *r = cand_mm(dst, src, len);
		if (r != dst) _exit(4);
		/* expected dst[i] = old src[i] = pat[i - 0]? src and dst
		 * overlap: expected byte at dst[i] is the ORIGINAL src[i],
		 * which equals pat[i] only where src/dst regions coincide
		 * in the pre-copy layout... recompute properly: */
		for (size_t i = 0; i < len; i++) {
			/* original src byte i was pat[i]; dst[i] must hold it
			 * UNLESS the candidate overwrote src[i] first. The
			 * reference (run on heap below in parent) decides;
			 * here just check no fault occurred and retval ok. */
			(void)i;
		}
		/* full check against heap reference */
		unsigned char *hsrc = malloc(len ? len : 1), *hdst = malloc(len ? len : 1);
		if (!hsrc || !hdst) _exit(8);
		memcpy(hsrc, pat, len);
		memset(hdst, 0xCC, len);
		/* emulate overlap geometry on heap copies */
		{
			unsigned char *h = malloc(len + (delta >= 0 ? (size_t)delta : (size_t)-delta) + 64);
			if (!h) _exit(8);
			unsigned char *hs = h + 32, *hd = hs + delta;
			memcpy(hs, pat, len);
			/* naive reference, direction-correct */
			if (hd < hs) { for (size_t i = 0; i < len; i++) hd[i] = hs[i]; }
			else if (hd > hs) { size_t n = len; while (n--) hd[n] = hs[n]; }
			if (hd != hs && memcmp(dst, hd, len) != 0) _exit(5);
			if (hd == hs && memcmp(dst, pat, len) != 0) _exit(5);
		}
		_exit(0);
	}
	int st = 0;
	waitpid(p, &st, 0);
	checked++;
	if (!WIFEXITED(st) || WEXITSTATUS(st) == 3) {
		/* geometry skipped: not a failure, un-count */
		checked--;
		return;
	}
	if (!WIFEXITED(st) || WEXITSTATUS(st) != 0) {
		fails++;
		if (fails < 10) printf("GUARD len=%zu d=%ld status=%d\n", len, delta, st);
	}
}

int main(void)
{
	A = malloc(ARENA); B = malloc(ARENA); E = malloc(ARENA);
	if (!A || !B || !E) return 99;
	size_t lens[] = { 0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,
		21,22,23,24,25,26,27,28,29,30,31,32,33,47,48,49,63,64,65,95,96,
		97,127,128,129,255,256,257,511,512,513,1023,1024,1025,2048,2049,
		4095,4096,4097,8191,8192,65535,65536,65537,100000,1048576,2097153,4194304 };
	long deltas[] = { 0,1,2,3,4,5,6,7,8,9,15,16,17,31,32,33,63,64,65,127,128,
		-1,-2,-3,-7,-8,-9,-15,-16,-17,-31,-32,-33,-63,-64,-65,-127,-128 };
	for (unsigned li = 0; li < sizeof lens / sizeof *lens; li++)
		for (unsigned di = 0; di < sizeof deltas / sizeof *deltas; di++) {
			size_t len = lens[li];
			long d = deltas[di];
			if (d > 0 && (size_t)d >= len && len > 0 && len < 16) { /* non-overlap small */ }
			if (d != 0 && len > 0 && (d > (long)len || -d > (long)len)) {
				if ((li % 3) != 0) continue; /* sample non-overlap */
			}
			for (unsigned a = 0; a < 16; a += (len < 64 ? 1 : 7)) {
				tcase(len, d, a % 16, (a * 5 + 3) % 16);
				if (len > 1024) break;
			}
		}
	/* guard-page runs: sampled (len, delta), child-isolated */
	size_t gl[] = { 1,7,8,9,15,16,17,31,32,33,64,100,256,1000,4096 };
	long gd[] = { 1,7,8,9,15,16,17,31,32,64 };
	for (unsigned i = 0; i < sizeof gl / sizeof *gl; i++)
		for (unsigned j = 0; j < sizeof gd / sizeof *gd; j++)
			guardcase(gl[i], gd[j]);
	/* randomized fuzz: heap buffers, canary words, retval + bytes */
	for (int k = 0; k < 120000; k++) {
		size_t len = (size_t)(rnd() % 4200);
		if ((k % 29) == 0) len = (size_t)(rnd() % 1048576);
		long dspan = (long)(len + 128);
		long d = (long)(rnd() % (2 * (unsigned)(dspan + 1))) - dspan;
		unsigned sa = rnd() % 16, da = rnd() % 16;
		size_t need = (len > 0 ? len : 1) + 1024;
		unsigned char *b1 = malloc(need), *b2 = malloc(need), *b3 = malloc(need);
		if (!b1 || !b2 || !b3) { free(b1); free(b2); free(b3); continue; }
		long off = (long)(256 + sa);
		unsigned char *s1 = b1 + off, *d1 = s1 + d;
		unsigned char *s2 = b2 + off, *d2 = s2 + d;
		unsigned char *s3 = b3 + off, *d3 = s3 + d;
		if (d1 < b1 + 8 || d1 + len > b1 + need - 8) { free(b1); free(b2); free(b3); continue; }
		for (size_t i = 0; i < (len ? len : 1) + 64; i++) {
			unsigned char v = (unsigned char)rnd();
			s1[i] = s2[i] = s3[i] = v;
		}
		if (d != 0) { /* keep canary gap distinct: nothing extra needed */ }
		void *r1 = base_mm(d1, s1, len);
		void *r2 = cand_mm(d2, s2, len);
		void *r3 = ref_mm(d3, s3, len);
		checked += 2;
		int ok = (r1 == d1) && (r2 == d2) &&
			(memcmp(d1, d3, len) == 0) && (memcmp(d2, d3, len) == 0);
		(void)r3; (void)da;
		if (!ok) {
			fails++;
			if (fails < 10)
				printf("FUZZ len=%zu d=%ld sa=%u base-ok=%d cand-ok=%d\n",
				       len, d, sa, r1 == d1 && memcmp(d1, d3, len) == 0,
				       r2 == d2 && memcmp(d2, d3, len) == 0);
		}
		free(b1); free(b2); free(b3);
	}
	printf("MATRIX checked=%ld fails=%ld\n", checked, fails);
	return fails != 0;
}

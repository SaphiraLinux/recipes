/* F8 mask-candidate vs staged generic: complete strstr, interleaved, checksums.
 * Original scratch test code, upstream musl MIT.
 */
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>
#include <time.h>
char *h_strstr(const char *h, const char *n);
static double now(void){struct timespec t;clock_gettime(1,&t);return (double)t.tv_sec*1e9+(double)t.tv_nsec;}
#define HN (64*1024)
static char H[HN+256] __attribute__((aligned(64)));
static char NDL[256];
static void gen_text(void){
	uint64_t r = 0xabcdef123456789ULL;
	static const char *words[] = {"the","quick","brown","fox","jumps","over","a","lazy","dog","and","runs","far","away","from","home","with","pack","of","many","words"};
	for (size_t p = 0; p < HN;) {
		const char *w = words[(r >>= 7) % 20];
		r ^= r << 13; r ^= r >> 7; r ^= r << 17;
		size_t l = strlen(w);
		if (p + l + 1 > HN) break;
		memcpy(H + p, w, l); p += l; H[p++] = ' ';
	}
	H[HN] = 0;
}
static double t_base, t_cand;
static uint64_t sb, sc;
static void run2(const char *name, const char *h, const char *n, long it, int rounds){
	t_base = t_cand = 0; sb = sc = 0;
	for (int rd = 0; rd < rounds; rd++) {
		double t0, t1, t2;
		if (rd % 2 == 0) {
			t0 = now();
			for (long i = 0; i < it; i++) { char *r = strstr(h, n); sb += (uint64_t)(r ? r - h + 1 : 0) + (uint64_t)i; }
			t1 = now();
			for (long i = 0; i < it; i++) { char *r = h_strstr(h, n); sc += (uint64_t)(r ? r - h + 1 : 0) + (uint64_t)i; }
			t2 = now();
		} else {
			t0 = now();
			for (long i = 0; i < it; i++) { char *r = h_strstr(h, n); sc += (uint64_t)(r ? r - h + 1 : 0) + (uint64_t)i; }
			t1 = now();
			for (long i = 0; i < it; i++) { char *r = strstr(h, n); sb += (uint64_t)(r ? r - h + 1 : 0) + (uint64_t)i; }
			t2 = now();
		}
		if (rd % 2 == 0) { t_base += t1 - t0; t_cand += t2 - t1; }
		else { t_cand += t1 - t0; t_base += t2 - t1; }
	}
	char *v0 = strstr(h, n), *v1 = h_strstr(h, n);
	long o0 = v0 ? v0 - h : -1, o1 = v1 ? v1 - h : -1;
	printf("%-22s base=%9.2fns cand=%9.2fns x=%5.2f off=%ld/%ld %s\n", name,
		t_base/(rounds*it), t_cand/(rounds*it), t_base/t_cand, o0, o1,
		(o0 == o1 && sb == sc) ? "OK" : "MISMATCH");
}
int main(void){
	gen_text();
	run2("1B frequent-e", H, "e", 20000, 6);
	run2("1B absent-Z", H, "Z", 3000, 6);
	{ char *p = H + 40; run2("2B early", p, "qu", 20000, 6); }
	run2("2B absent", H, "xy", 1500, 6);
	run2("2B late", H + 30000, "th", 3000, 6);
	run2("3B mid", H + 200, "fox", 20000, 6);
	run2("3B absent", H, "dzg", 1500, 6);
	run2("4B mid", H + 1000, "away", 8000, 6);
	run2("4B absent", H, "zzzz", 1500, 6);
	{ memcpy(NDL, H + 10, 32); NDL[32] = 0; run2("32B early", H, NDL, 5000, 6); }
	{ size_t L = 30000; memcpy(NDL, H + L, 32); NDL[32] = 0; run2("32B late", H, NDL, 2000, 4); }
	{ size_t L = 30000; memcpy(NDL, H + L, 31); NDL[31] = 'Z'; NDL[32] = 0; run2("32B absent", H, NDL, 2000, 4); }
	{ memcpy(NDL, H + 500, 128); NDL[128] = 0; run2("128B mid", H, NDL, 2000, 4); }
	{
		static char A[HN+2]; memset(A, 'a', HN); A[HN] = 0;
		memset(NDL, 'a', 63); NDL[63] = 'b'; NDL[64] = 0;
		run2("ADV a*63+b absent", A, NDL, 200, 4);
		memset(NDL, 'a', 15); NDL[15] = 'b'; NDL[16] = 0;
		run2("ADV a*15+b absent", A, NDL, 300, 4);
	}
	{
		static char P[HN+2];
		for (size_t i = 0; i < HN; i++) P[i] = "abc"[i % 3];
		P[HN] = 0;
		memcpy(NDL, "abcabcabd", 9); NDL[9] = 0;
		run2("PERIODIC near-miss", P, NDL, 800, 4);
	}
	{
		char hs[64]; memset(hs, 'x', 60); memcpy(hs + 50, "needle", 6); hs[60] = 0;
		run2("SHORT h=60 n=6", hs, "needle", 50000, 6);
		run2("SHORT absent", hs, "zzz", 50000, 6);
	}
	return 0;
}

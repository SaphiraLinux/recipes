/* Complete-function differential: candidate mbsrtowcs (AVX2 fast path)
 * vs baseline. Prints one deterministic line per case; outputs are diffed.
 * Original Saphira test code under upstream musl license (MIT, no change).
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <wchar.h>
#include <locale.h>
#include <errno.h>
#include <sys/mman.h>
#include <stdint.h>

static void show(const char *name, long long ret, const char *orig,
		const char *src, int err, wchar_t *ws, size_t wcap)
{
	long long off = (src == NULL) ? -1LL : (long long)(src - orig);
	printf("%s ret=%lld off=%lld err=%d", name, ret, off, err);
	if (ws && ret > 0 && ret < 64) {
		printf(" ws=");
		for (long long i = 0; i < ret; i++) printf("%08lx,", (unsigned long)ws[i]);
		printf("term=%d", ws[ret] == 0);
	}
	printf("\n");
}

/* converting mode, ws provided */
static void t_conv(const char *name, const unsigned char *in, size_t len,
		size_t wn, mbstate_t *pst)
{
	static wchar_t ws[5200];
	const char *src;
	size_t r;
	for (size_t i = 0; i < 5200; i++) ws[i] = 0xDEADBEEF;
	memcpy((char *)ws + 5000*sizeof(wchar_t), "GUARD", 6);
	src = (const char *)in;
	errno = 0;
	r = mbsrtowcs(ws, &src, wn, pst);
	show(name, (long long)r, (const char *)in, src, errno, ws, 5200);
}

/* counting mode */
static void t_count(const char *name, const unsigned char *in, size_t len, size_t wn)
{
	const char *src = (const char *)in;
	size_t r;
	errno = 0;
	r = mbsrtowcs(NULL, &src, wn, NULL);
	long long off = (src == NULL) ? -1LL : (long long)(src - (const char *)in);
	printf("%s ret=%lld off=%lld err=%d\n", name, (long long)r, off, errno);
}

int main(void)
{
	static unsigned char big[8192+64];
	unsigned char tmp[512];
	mbstate_t st;
	wchar_t wc;
	size_t r;

	if (!setlocale(LC_CTYPE, "C.UTF-8")) { printf("no C.UTF-8\n"); return 2; }
	printf("mbcurmax=%d\n", (int)MB_CUR_MAX);

	/* 1. pure ASCII, lengths incl. block/page edges, alignments */
	for (int al = 0; al < 8; al++) {
		for (int L = 0; L <= 70; L++) {
			unsigned char *b = big + al;
			memset(b, 0x41, L); b[L] = 0;
			char nm[64]; snprintf(nm, 64, "A al=%d L=%d", al, L);
			t_conv(nm, b, L+1, 5000, NULL);
		}
	}
	{
		unsigned char *b = big;
		memset(b, 0x41, 5000); b[5000] = 0;
		t_conv("A long5000", b, 5001, 5100, NULL);
		t_conv("A long5000-wncut", b, 5001, 100, NULL);
		t_count("C long5000", b, 5001, 5100);
	}
	/* 2. NUL positions */
	for (int L = 1; L < 130; L += 1) {
		unsigned char *b = big + 3;
		memset(b, 0x41, 140); b[140] = 0;
		if (L < 140) b[L] = 0;
		char nm[64]; snprintf(nm, 64, "NUL pos=%d", L);
		t_conv(nm, b, 141, 5000, NULL);
		if (L % 17 == 0) t_count(nm, b, 141, 5000);
	}
	/* 3. multibyte at offsets incl. 32B-block straddle */
	{
		static const unsigned char seq[] = {0xE2,0x82,0xAC,0x41,0xF0,0x9F,0x98,0x80,0xC3,0xA9,0x7F,0x00};
		for (int al = 0; al < 40; al++) {
			unsigned char *b = big + al;
			memcpy(b, seq, sizeof seq);
			char nm[64]; snprintf(nm, 64, "MB al=%d", al);
			t_conv(nm, b, sizeof seq, 5000, NULL);
		}
	}
	/* 4. mixed ASCII runs + multibyte */
	{
		unsigned char *b = big + 5;
		int p = 0;
		for (int i = 0; i < 200; i++) b[p++] = 0x30 + (i % 10);
		b[p++] = 0xE2; b[p++] = 0x82; b[p++] = 0xAC;
		for (int i = 0; i < 300; i++) b[p++] = 0x61 + (i % 26);
		b[p++] = 0xF0; b[p++] = 0x9F; b[p++] = 0x98; b[p++] = 0x80;
		for (int i = 0; i < 50; i++) b[p++] = 0x41;
		b[p] = 0;
		t_conv("MIX full", b, p+1, 5000, NULL);
		t_conv("MIX wn150", b, p+1, 150, NULL);
		t_conv("MIX wn201", b, p+1, 201, NULL);
		t_count("MIXC full", b, p+1, 5000);
	}
	/* 5. malformed */
	{
		struct { const char *n; unsigned char d[8]; int l; } m[] = {
			{"BAD lone-cont", {0x41,0x80,0x41,0x00}, 4},
			{"BAD trunc2", {0x41,0xC3,0x00}, 3},
			{"BAD trunc3", {0x41,0xE2,0x82,0x00}, 4},
			{"BAD overlong2", {0xC0,0xAF,0x00}, 3},
			{"BAD overlong3", {0xE0,0x80,0x80,0x00}, 4},
			{"BAD surrogate", {0xED,0xA0,0x80,0x00}, 4},
			{"BAD F5", {0xF5,0x80,0x80,0x80,0x00}, 5},
			{"BAD FE", {0xFE,0x00}, 2},
			{"BAD FF", {0x41,0xFF,0x00}, 3},
			{"BAD badcont", {0xC3,0x28,0x00}, 3},
		};
		for (size_t i = 0; i < sizeof m/sizeof m[0]; i++) {
			t_conv(m[i].n, m[i].d, m[i].l, 5000, NULL);
			t_count(m[i].n, m[i].d, m[i].l, 5000);
		}
	}
	/* 6/7. wn truncation incl. 0 */
	{
		unsigned char *b = big + 1;
		memset(b, 0x42, 100); b[100] = 0;
		t_conv("WN0", b, 101, 0, NULL);
		t_conv("WN1", b, 101, 1, NULL);
		memcpy(tmp, "\x43\xE2\x82\xAC\x44\x00", 6);
		t_conv("WNmid2-1", tmp, 6, 1, NULL);
		t_conv("WNmid2-2", tmp, 6, 2, NULL);
		t_count("WNC0", b, 101, 0);
		t_count("WNC10", b, 101, 10);
	}
	/* 10. mbstate resume */
	{
		memset(&st, 0, sizeof st);
		r = mbrtowc(&wc, "\xE2", 1, &st);
		printf("SETUP mbrtowc-partial ret=%lld\n", (long long)r);
		memcpy(tmp, "\x82\xAC\x41\x00", 4);
		t_conv("RESUME", tmp, 4, 100, &st);
	}
	/* 12. mbsnrtowcs */
	{
		memset(tmp, 0, sizeof tmp);
		memcpy(tmp, "hello\xE2\x82\xACworld", 14);
		const char *s; wchar_t w2[32]; size_t rr;
		s = (char *)tmp;
		rr = mbsnrtowcs(w2, &s, 7, 32, NULL);
		printf("SNRT nms=7 ret=%lld off=%lld w0=%lx w6term=%d\n",
			(long long)rr, (long long)(s-(char*)tmp),
			(unsigned long)w2[0], w2[rr]==0);
		s = (char *)tmp;
		rr = mbsnrtowcs(w2, &s, 15, 32, NULL);
		printf("SNRT nms=15 ret=%lld off=%lld\n", (long long)rr,
			(long long)(s ? s-(char*)tmp : -1LL));
	}
	/* 11. guard page: mapped region ends at PROT_NONE, huge wn */
	{
		size_t P = 4096;
		unsigned char *map = mmap(0, 2*P, PROT_READ|PROT_WRITE,
			MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
		if (map == MAP_FAILED) { printf("mmap failed\n"); return 2; }
		if (mprotect(map+P, P, PROT_NONE)) { printf("mprotect failed\n"); return 2; }
		for (int off = 0; off < 64; off += 7) {
			unsigned char *b = map + P - 64 + off;
			size_t room = 64 - off;
			/* ASCII fill + NUL at last mapped byte, wn huge */
			memset(b, 0x41, room - 1); b[room-1] = 0;
			char nm[64]; snprintf(nm, 64, "G off=%d nul-end", off);
			{ static wchar_t ws[128]; const char *s = (char*)b;
			  errno = 0; r = mbsrtowcs(ws, &s, 1<<20, NULL);
			  printf("%s ret=%lld off=%lld err=%d\n", nm, (long long)r,
				(long long)(s ? s-(char*)b : -1LL), errno); }
			/* 2-byte char + NUL ending exactly at boundary, wn huge */
			if (room >= 4) {
				memset(b, 0x41, room - 3);
				b[room-3] = 0xC3; b[room-2] = 0xA9; b[room-1] = 0;
				snprintf(nm, 64, "G off=%d mb-nul-end", off);
				{ static wchar_t ws[128]; const char *s = (char*)b;
				  errno = 0; r = mbsrtowcs(ws, &s, 1<<20, NULL);
				  printf("%s ret=%lld off=%lld err=%d wlast=%lx\n", nm, (long long)r,
					(long long)(s ? s-(char*)b : -1LL), errno,
					(unsigned long)(r < 128 ? ws[r > 0 ? r-1 : 0] : 0)); }
			}
			/* early NUL + huge wn */
			memset(b, 0x41, room - 1); b[room-1] = 0; b[3 % room] = 0;
			snprintf(nm, 64, "G off=%d nul-early", off);
			{ static wchar_t ws[128]; const char *s = (char*)b;
			  errno = 0; r = mbsrtowcs(ws, &s, 1<<20, NULL);
			  printf("%s ret=%lld off=%lld err=%d\n", nm, (long long)r,
				(long long)(s ? s-(char*)b : -1LL), errno); }
		}
		munmap(map, 2*P);
	}
	/* 9. C locale path sanity */
	{
		setlocale(LC_ALL, "C");
		printf("mbcurmax-C=%d\n", (int)MB_CUR_MAX);
		memcpy(tmp, "abc", 4);
		const char *s = (char*)tmp; static wchar_t ws[8];
		errno = 0; r = mbsrtowcs(ws, &s, 8, NULL);
		printf("CLOC ret=%lld w0=%lx w1=%lx w2=%lx\n", (long long)r,
			(unsigned long)ws[0], (unsigned long)ws[1], (unsigned long)ws[2]);
	}
	return 0;
}

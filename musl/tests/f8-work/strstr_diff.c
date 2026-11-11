/* F8 strstr differential: harness+SIMD-candidate vs staged generic libc.
 * Offsets must match exactly. Original scratch test code, upstream musl MIT.
 */
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdlib.h>
#include <sys/mman.h>
char *h_strstr(const char *h, const char *n);
static long fails, total;
static void check(const char *h, const char *n){
	char *e = strstr(h, n), *a = h_strstr(h, n);
	long eo = e ? (long)(e - h) : -1, ao = a ? (long)(a - h) : -1;
	total++;
	if (eo != ao) {
		fails++;
		if (fails < 15) printf("DIFF hlen=%zu nlen=%zu exp=%ld got=%ld h0=%02x%02x n=%02x%02x%02x%02x\n",
			strlen(h), strlen(n), eo, ao,
			((unsigned char*)h)[0], ((unsigned char*)h)[1],
			((unsigned char*)n)[0], ((unsigned char*)n)[1],
			((unsigned char*)n)[2], ((unsigned char*)n)[3]);
	}
}
static uint64_t xst;
static uint64_t rnd64(void){xst^=xst<<13;xst^=xst>>7;xst^=xst<<17;return xst;}
int main(void){
	static unsigned char big[512+64], ndl[8];
	xst = 0x51ab51ab51ab51abULL;
	/* 1. random haystacks x alignments x lengths; random + repetitive needles */
	for (int al = 0; al < 64; al += 1) for (int len = 0; len < 130; len++) {
		unsigned char *h = big + al;
		for (int i = 0; i < len; i++) {
			uint64_t r = rnd64();
			int c = (r >> 37) & 7;
			if (c < 4) h[i] = (unsigned char)(0x20 + (r % 0x5F));
			else if (c < 5) h[i] = (unsigned char)(0x80 + (r % 0x40));
			else if (c < 6) h[i] = 'a';
			else h[i] = (unsigned char)(1 + (r % 254));
		}
		if (len) h[rnd64() % len] = 'q';	/* frequent byte */
		h[len] = 0;
		/* needles 2,3,4 + controls 1,5 */
		for (int nl = 1; nl <= 5; nl++) {
			for (int cls = 0; cls < 6; cls++) {
				for (int i = 0; i < nl; i++) {
					uint64_t r = rnd64();
					if (cls == 0) ndl[i] = (unsigned char)(0x20 + (r % 0x5F));
					else if (cls == 1) ndl[i] = 'a';
					else if (cls == 2) ndl[i] = (unsigned char)(0x80 + (r % 0x40));
					else if (cls == 3 && i < len) ndl[i] = h[(r>>11) % len] ? h[(r>>11) % len] : 'x';
					else if (cls == 4 && nl > 1) ndl[i] = (i == nl-1) ? 'Z' : 'a';
					else ndl[i] = (unsigned char)(1 + (r % 254));
					if (!ndl[i]) ndl[i] = 'x';
				}
				ndl[nl] = 0;
				check((char*)h, (char*)ndl);
				/* guaranteed-hit slice at sweeping offset */
				if (len > nl + 50) {
					int at = (len - nl - 1) % 51;
					memcpy(ndl, h + at, nl); ndl[nl] = 0;
					if (ndl[0] && (nl < 2 || ndl[1]) && (nl < 3 || ndl[2]) && (nl < 4 || ndl[3]))
						check((char*)h, (char*)ndl);
				}
			}
		}
	}
	/* 2. overlapping matches + repetitive haystacks */
	{
		struct { const char *h; const char *n; } t[] = {
			{"aaaa", "aa"}, {"aaabaaa", "aab"}, {"abcabcabc", "abc"},
			{"abcabcabc", "bca"}, {"abababab", "abab"}, {"aaaaab", "aab"},
			{"\x80\x81\x80\x81x", "\x80\x81"}, {"xy\xff\xfe""xy", "\xff\xfe"},
			{"", "ab"}, {"a", "ab"}, {"ab", "abc"}, {"abc", "abcd"},
			{"abc", "abc"}, {"abc", "abcd"}, {"abc", "x"},
		};
		for (size_t i = 0; i < sizeof t/sizeof t[0]; i++)
			for (int nl = 1; nl <= 5; nl++) {
				char nn[6]; memcpy(nn, t[i].n, nl); nn[nl] = 0;
				if (nl >= 2 && !nn[1]) continue;
				check(t[i].h, nn);
			}
	}
	/* 3. page-boundary tests: mmap 3 pages, PROT_NONE last */
	{
		size_t P = 4096;
		unsigned char *map = mmap(0, 3*P, PROT_READ|PROT_WRITE,
			MAP_PRIVATE|MAP_ANONYMOUS, -1, 0);
		if (map == MAP_FAILED) { printf("mmap failed\n"); return 2; }
		if (mprotect(map+2*P, P, PROT_NONE)) { printf("mprotect failed\n"); return 2; }
		for (int endoff = 0; endoff < 80; endoff++) {
			/* haystack ends at 2P-endoff; NUL at last mapped byte */
			unsigned char *base = map + 2*P - 128 - endoff;
			size_t room = 128 + endoff;
			for (size_t k = 0; k + 1 < room; k++)
				base[k] = (k % 7 == 3) ? 'm' : (unsigned char)('a' + (k % 26));
			base[room-1] = 0;
			for (int nl = 1; nl <= 5; nl++) {
				/* slice hits sweeping the boundary region */
				for (int at = 0; at < 40 && (size_t)(at + nl) < room; at += 3) {
					memcpy(ndl, base + at, nl); ndl[nl] = 0;
					if (!ndl[0] || (nl > 1 && !ndl[1])) continue;
					check((char*)base, (char*)ndl);
				}
				/* absent needle */
				memcpy(ndl, "QZ9", nl > 3 ? 3 : nl); ndl[nl > 3 ? 3 : nl] = 0;
				if (nl <= 3) check((char*)base, (char*)ndl);
				/* match crossing the 1P|2P page boundary */
				if (room > P + 8) {
					unsigned char *b2 = map + P - 20;
					for (int k = 0; k < 60; k++) b2[k] = 'a' + (k % 26);
					b2[60] = 0;
					memcpy(ndl, b2 + (20 - nl + 1), nl); ndl[nl] = 0;
					check((char*)b2, (char*)ndl);
				}
			}
		}
		munmap(map, 3*P);
	}
	printf("strstr_diff: total=%ld fails=%ld\n", total, fails);
	return fails != 0;
}

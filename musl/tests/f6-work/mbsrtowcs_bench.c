/* Bench: complete mbsrtowcs, base vs candidate (compiled per-root).
 * Original Saphira test code under upstream musl license (MIT, no change).
 */
#include <stdio.h>
#include <string.h>
#include <wchar.h>
#include <locale.h>
#include <time.h>
static double now(void){struct timespec t;clock_gettime(1,&t);return t.tv_sec+t.tv_nsec*1e-9;}
static unsigned char in[2048] __attribute__((aligned(64)));
static wchar_t out[2048];
int main(void){
	setlocale(LC_CTYPE, "C.UTF-8");
	struct { const char *n; int len; int kind; } tc[] = {
		{"ascii40", 40, 0}, {"ascii200", 200, 0}, {"ascii1500", 1500, 0},
		{"mix553", 553, 1}, {"mb12", 12, 2},
	};
	for (size_t t = 0; t < sizeof tc/sizeof tc[0]; t++) {
		int L = tc[t].len;
		if (tc[t].kind == 0) { memset(in, 0x41, L); in[L] = 0; }
		else if (tc[t].kind == 2) {
			unsigned char s[]={0xE2,0x82,0xAC,0x41,0xF0,0x9F,0x98,0x80,0xC3,0xA9,0x7F,0x00};
			memcpy(in, s, 12); L = 12;
		} else {
			int p = 0;
			for (int i = 0; i < 200; i++) in[p++] = 0x30+(i%10);
			in[p++]=0xE2; in[p++]=0x82; in[p++]=0xAC;
			for (int i = 0; i < 300; i++) in[p++] = 0x61+(i%26);
			in[p++]=0xF0; in[p++]=0x9F; in[p++]=0x98; in[p++]=0x80;
			for (int i = 0; i < 50; i++) in[p++] = 0x41;
			in[p] = 0; L = p;
		}
		volatile size_t sink = 0;
		double t0 = now();
		for (long i = 0; i < 500000; i++) {
			const char *s = (char*)in;
			sink += mbsrtowcs(out, &s, 2048, NULL);
		}
		double t1 = now();
		printf("%s: %.3fns/conv sink=%zu out0=%lx\n", tc[t].n,
			(t1-t0)/500000*1e9, sink, (unsigned long)out[0]);
	}
	return 0;
}

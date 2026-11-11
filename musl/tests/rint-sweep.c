/* rint vs roundsd-imm4: correctness + flag sweep. Compares musl rint()
 * against a single roundsd with MXCSR rounding, over specials,
 * subnormals, randoms, and all 4 rounding modes, checking value bits
 * AND exception flags. A clean sweep means the asm form is a drop-in. */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#include <fenv.h>

static double r_hw(double x) { double r; __asm__ volatile("roundsd $4, %1, %0" : "=x"(r) : "x"(x)); return r; }

static long fails = 0, checked = 0, denote = 0;
static void cmp(double x, int mode)
{
	union { double f; uint64_t i; } a, b;
	feclearexcept(FE_ALL_EXCEPT);
	a.f = rint(x);
	int fa = fetestexcept(FE_ALL_EXCEPT);
	feclearexcept(FE_ALL_EXCEPT);
	b.f = r_hw(x);
	int fb = fetestexcept(FE_ALL_EXCEPT);
	checked++;
	if (a.i != b.i || fa != fb) {
		if (a.i == b.i && ((fa ^ fb) == 0x02)) {
			denote++; /* denormal-operand status bit only: musl sets, hw doesn't */
			return;
		}
		if (fails < 12)
			printf("DIFF x=%a mode=%d musl=%a(%x) hw=%a(%x)\n", x, mode, a.f, fa, b.f, fb);
		fails++;
	}
}

int main(void)
{
	int modes[] = { FE_TONEAREST, FE_DOWNWARD, FE_UPWARD, FE_TOWARDZERO };
	double specials[] = { 0.0, -0.0, 1.5, -1.5, 2.5, -2.5, 0.5, 1e16,
		-1e16, 4503599627370496.0, 9007199254740992.0, 4.9406564584124654e-324,
		2.2250738585072014e-308, 1.7976931348623157e308, 1.0/0.0, -1.0/0.0,
		0.0/0.0, -0.0/0.0 };
	for (int m = 0; m < 4; m++) {
		fesetround(modes[m]);
		for (unsigned i = 0; i < sizeof specials / sizeof *specials; i++)
			cmp(specials[i], m);
		union { double f; uint64_t i; } u;
		for (int j = 0; j < 20000; j++) {
			uint64_t k = (uint64_t)j * 7919;
			u.i = k & 0xfffffffffffffULL; cmp(u.f, m);
			u.i = 0x3ff0000000000000ULL + (k & 0xfffffffffffffULL); cmp(u.f, m);
		}
		uint64_t s = 0x123456789abcdefULL + m;
		for (int k = 0; k < 500000; k++) {
			s = s * 6364136223846793005ULL + 1449691640888963407ULL;
			u.i = s & 0x7fffffffffffffffULL;
			if ((u.i >> 52) == 0x7ff) continue;
			cmp(u.f, m);
		}
		printf("mode %d: fails=%ld denormal-bit-only=%ld\n", m, fails, denote);
	}
	fesetround(FE_TONEAREST);
	printf("TOTAL checked=%ld fails=%ld denormal-bit-only=%ld\n", checked, fails, denote);
	return fails != 0;
}

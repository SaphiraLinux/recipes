/* F2 DAZ value check: -denorm-min under DAZ=1, generic vs cand. */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdint.h>
#include <math.h>
#include <fenv.h>
static double c_floor(double x)
{ double y; __asm__ volatile("roundsd $9, %1, %0" : "=x"(y) : "x"(x)); return y; }
static unsigned get_mxcsr(void)
{ unsigned m; __asm__ volatile("stmxcsr %0" : "=m"(m)); return m; }
static void set_mxcsr(unsigned m)
{ __asm__ volatile("ldmxcsr %0" :: "m"(m)); }
int main(void)
{
	double v[] = { -0x1p-1074, 0x1p-1074, -0x1.fffffffffffffp-1023 };
	for (int d = 0; d < 2; d++) {
		unsigned base = (get_mxcsr() & ~(0x8040U | 0x3fU)) | (d ? 0x40U : 0U);
		for (unsigned i = 0; i < 3; i++) {
			union { double f; uint64_t u; } a, b;
			int fa, fb;
			set_mxcsr(base);
			feclearexcept(FE_ALL_EXCEPT);
			a.f = floor(v[i]); fa = fetestexcept(FE_ALL_EXCEPT);
			set_mxcsr(base);
			feclearexcept(FE_ALL_EXCEPT);
			b.f = c_floor(v[i]); fb = fetestexcept(FE_ALL_EXCEPT);
			printf("DAZ=%d x=%a gen=%a(%x) cand=%a(%x) %s\n",
			       d, v[i], a.f, fa, b.f, fb,
			       (a.u == b.u && fa == fb) ? "same" : "DIFF");
		}
	}
	return 0;
}

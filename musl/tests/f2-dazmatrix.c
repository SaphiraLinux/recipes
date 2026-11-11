/* F2 DAZ matrix: all four functions, generic vs suppress-imm
 * candidates (+ nearbyint combo), subnormal inputs, DAZ=1. */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdint.h>
#include <math.h>
#include <fenv.h>
#include <float.h>
double nearby_combo(double);
extern double rint_exp(double);
static double c_floor(double x)
{ double y; __asm__ volatile("roundsd $9, %1, %0" : "=x"(y) : "x"(x)); return y; }
static double c_ceil(double x)
{ double y; __asm__ volatile("roundsd $10, %1, %0" : "=x"(y) : "x"(x)); return y; }
static double c_trunc(double x)
{ double y; __asm__ volatile("roundsd $11, %1, %0" : "=x"(y) : "x"(x)); return y; }
static double c_nearby(double x)
{ double y; __asm__ volatile("roundsd $12, %1, %0" : "=x"(y) : "x"(x)); return y; }
static unsigned get_mxcsr(void)
{ unsigned m; __asm__ volatile("stmxcsr %0" : "=m"(m)); return m; }
static void set_mxcsr(unsigned m)
{ __asm__ volatile("ldmxcsr %0" :: "m"(m)); }
int main(void)
{
	fesetround(FE_TONEAREST);
	double v[] = { -0x1p-1074, 0x1p-1074, -0x1.fffffffffffffp-1023,
		0x1.fffffffffffffp-1023, DBL_MIN, -DBL_MIN };
	struct { const char *n; double (*g)(double); double (*c)(double); } t[] = {
		{ "floor", floor, c_floor }, { "ceil", ceil, c_ceil },
		{ "trunc", trunc, c_trunc }, { "nearbyint", nearbyint, c_nearby },
		{ "nearby-combo", nearbyint, nearby_combo },
	};
	unsigned base = (get_mxcsr() & ~(0x8040U | 0x3fU)) | 0x40U;
	for (unsigned i = 0; i < sizeof t / sizeof *t; i++)
		for (unsigned k = 0; k < 6; k++) {
			union { double f; uint64_t u; } a, b;
			int fa, fb;
			set_mxcsr(base);
			feclearexcept(FE_ALL_EXCEPT);
			a.f = t[i].g(v[k]); fa = fetestexcept(FE_ALL_EXCEPT);
			set_mxcsr(base);
			feclearexcept(FE_ALL_EXCEPT);
			b.f = t[i].c(v[k]); fb = fetestexcept(FE_ALL_EXCEPT);
			printf("DAZ %-12s x=%a gen=%a(%x) cand=%a(%x) %s\n",
			       t[i].n, v[k], a.f, fa, b.f, fb,
			       (a.u == b.u && fa == fb) ? "same" : "DIFF");
		}
	return 0;
}

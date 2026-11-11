/* nearbyint/lrint interaction check: both call rint internally.
 * Compares the experimental tree against the generic-C tree across
 * rounding modes, subnormals, overflows and flag states. */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#include <fenv.h>
#include <limits.h>

static long fails = 0, n = 0;
static void t2(double x, int mode)
{
	union { double f; uint64_t i; } a, b;
	feclearexcept(FE_ALL_EXCEPT);
	a.f = nearbyint(x);
	int fa = fetestexcept(FE_ALL_EXCEPT);
	(void)a;
	n++;
	(void)mode;
	(void)b;
	(void)fa;
}

int main(void)
{
	int modes[] = { FE_TONEAREST, FE_DOWNWARD, FE_UPWARD, FE_TOWARDZERO };
	double vals[] = { 0.0, -0.0, 0.5, 1.5, 2.5, -2.5, 0.49999999999999994,
		4503599627370496.0, -4503599627370496.0, 1e16, -1e16,
		4.9406564584124654e-324, 2.2250738585072014e-324,
		9007199254740991.0, 9007199254740993.0, 1e300,
		1.0 / 0.0, -1.0 / 0.0, 0.0 / 0.0 };
	union { double f; uint64_t i; } u;
	for (int m = 0; m < 4; m++) {
		fesetround(modes[m]);
		for (unsigned i = 0; i < sizeof vals / sizeof *vals; i++) {
			double x = vals[i];
			feclearexcept(FE_ALL_EXCEPT);
			double r = nearbyint(x);
			int fr = fetestexcept(FE_ALL_EXCEPT);
			feclearexcept(FE_ALL_EXCEPT);
			long v = lrint(x);
			int fl = fetestexcept(FE_ALL_EXCEPT);
			if (n < 2000000000L)
				printf("m=%d x=%a nearby=%a(%x) lrint=%ld(%x)\n",
					m, x, r, fr, v, fl);
			n++;
			(void)u;
		}
	}
	fesetround(FE_TONEAREST);
	printf("done n=%ld (compare the two runs by diff)\n", n);
	return 0;
}

/* Saphira FP: directed floor/ceil/trunc/rint/nearbyint values,
 * rounding-mode spot checks, and NaN propagation. Fast smoke over
 * the F3/F4 matrices (full matrices live in the Sinew harnesses). */
#include <fenv.h>
#include <math.h>
#include <stdio.h>
#include "test.h"


static int fails;

#define DCHECK(fn, x, want) do { \
	double g = fn(x); \
	if (!(g == (want) && !(g != g && (want) == (want)))) { \
		if (!(g != g && (want) != (want))) { \
			t_error(#fn "(%a) = %a, want %a\n", (x), g, (double)(want)); \
			fails++; \
		} \
	} \
} while (0)

int main(void)
{
#pragma STDC FENV_ACCESS ON
	double s;

	DCHECK(floor, 0.5, 0.0);
	DCHECK(floor, -0.5, -1.0);
	DCHECK(ceil, 0.5, 1.0);
	DCHECK(ceil, -0.5, -0.0);
	DCHECK(trunc, 1.9, 1.0);
	DCHECK(trunc, -1.9, -1.0);
	DCHECK(rint, 2.5, 2.0);
	DCHECK(rint, 3.5, 4.0);
	DCHECK(nearbyint, 2.5, 2.0);
	DCHECK(nearbyint, 3.5, 4.0);
	DCHECK(floor, 1.0, 1.0);
	if (fails)
		return 1;

	/* rounding modes move rint/nearbyint; floor/ceil/trunc ignore them */
	fesetround(FE_DOWNWARD);
	s = rint(2.5);
	if (s != 2.0) {
		t_error("rint downward %a\n", s);
		return 1;
	}
	fesetround(FE_UPWARD);
	s = nearbyint(2.5);
	if (s != 3.0) {
		t_error("nearbyint upward %a\n", s);
		return 1;
	}
	fesetround(FE_TONEAREST);

	/* NaN in -> NaN out, no trap in default mode */
	s = floor(0.0 / 0.0);
	if (s == s) {
		t_error("floor(NaN) not NaN\n");
		return 1;
	}
	return t_status;
}

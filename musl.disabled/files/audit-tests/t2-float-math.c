/* t2: floatscan/strtod/math (upstream dd856098, 6426a515, 50979c5b,
 * a9764402, ec9daea2, 27b485a3, 3e80328d, 26c909bb, af839d43).
 * Prints observed values; the runner diffs baseline vs patched. */
#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <math.h>
#include <float.h>

static void t(const char *s)
{
	errno = 0;
	char *e;
	double v = strtod(s, &e);
	printf("strtod %-58s -> %a errno=%d\n", s, v, errno);
}

int main(void)
{
	/* floatscan OOB trigger from the upstream report (ld-80 too). */
	t("710542735760100185871124267578125e-33");
	/* Around the double normal/denormal boundary. */
	t("2.2250738585072014e-308");
	t("2.225073858507201383090232717332404064821000365370e-308");
	t("2.2250738585072009e-308");
	t("1.112536929253600691545116358666692045322978893871e-308");
	t("4.9406564584124654e-324");
	t("0.1");

	/* Long-double hex vs decimal agreement. */
	long double a = strtold("0.1", 0);
	long double b = strtold("0x1.9999999999999999999999999999p-4", 0);
	printf("ld-agree: %La %La %s\n", a, b, a == b ? "same" : "DIFFER");

	/* fmaf subnormal double-rounding halfway case (upstream vector). */
	float f = fmaf(0x20201p-92f, 0x1fe01p-92f, 0x1p-130f);
	printf("fmaf-subnormal: %a (correct 0x1.00002p-130)\n", f);

	/* powl negative base, odd integer exponent, over/underflow. */
	printf("powl1: %La (correct -inf)\n", powl(-1.5L, 50001));
	printf("powl2: %La (correct -0)\n", powl(-0.5L, 50001));
	printf("powl3: %La (correct -inf)\n", powl(-0x1p-16444L, -1));

	/* expl on x86: large-magnitude negative must underflow to zero. */
	printf("expl-neg: %La (correct 0)\n", expl(-40000.0L));
	/* expl threshold case: 2^trunc(x) stays nonzero below -16384. */
	printf("expl-threshold: %La (correct 0)\n", expl(-16384.0L));
	printf("expl-mid: %La (correct 0)\n", expl(-20000.0L));

	/* acosh domain and float/double consistency. */
	printf("acosh-neg: %f (correct nan)\n", acosh(-1.0));
	printf("acoshf-consistency: %a vs %a\n",
		(double)acoshf(2.0f), acosh(2.0));
	/* acoshf for x<0 must match the double version rounded to float. */
	printf("acoshf-neg: %a vs %a\n",
		(double)acoshf(-1.0f), acosh(-1.0));
	return 0;
}

/* t14: volatile-operand math probes (defeats compile-time folding, so the
 * observed values are genuinely produced by the linked libc). */
#include <stdio.h>
#include <math.h>

int main(void)
{
	volatile float fa = 0x20201p-92f, fb = 0x1fe01p-92f, fc = 0x1p-130f;
	volatile float f = fmaf(fa, fb, fc);
	printf("fmaf-volatile: %a (fixed 0x1.00002p-130)\n", (double)f);

	volatile double da = -1.5;
	volatile int di = 50001;
	printf("powl-volatile: %La\n", powl((long double)da, di));

	volatile long double le = -16384.0L;
	printf("expl-volatile: %La (fixed 0)\n", expl(le));

	volatile double an = -1.0, an2 = -0.5, an3 = -2.0;
	printf("acosh-volatile: %f %f %f (all nan)\n",
		acosh(an), acosh(an2), acosh(an3));
	volatile float af = -1.0f;
	printf("acoshf-volatile: %a vs %a\n",
		(double)acoshf(af), acosh((double)af));
	return 0;
}

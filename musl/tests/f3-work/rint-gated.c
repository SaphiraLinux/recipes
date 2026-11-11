/* F3 candidate: rint with real-op flag restoration on subnormals.
 * Base technique from 0004 (arch roundsd following the MXCSR mode).
 * The F2b finding (combo silent on DE) and the F3 trap policy require
 * the denormal-operand status bit to be preserved exactly as the
 * generic C implementation raises it — including trapping when DM is
 * unmasked. ldmxcsr cannot do that (it never traps), so the cold path
 * executes one real, value-discarded operation on the original input:
 * subnormal+1.0 raises PE|DE (DAZ=0) and stays silent under DAZ=1,
 * exactly matching generic in both modes, masked and trapped.
 * No MXCSR access at all; hot path is roundsd + bit test only. */
#include <math.h>
#include <stdint.h>

double rint(double x)
{
	union {double f; uint64_t i;} u = {x};
	uint64_t a = u.i & 0x7fffffffffffffff;
	double y;

	__asm__ ("roundsd $4, %1, %0" : "=x" (y) : "x" (x));
	if (a != 0 && a < 0x0010000000000000) {
		volatile double t = x + 1.0;	/* sacrificial: flags only */
		(void)t;
	}
	return y;
}

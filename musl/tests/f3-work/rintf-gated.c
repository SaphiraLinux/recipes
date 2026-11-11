/* F3 candidate: rintf with real-op flag restoration (see rint-gated.c). */
#include <math.h>
#include <stdint.h>

float rintf(float x)
{
	union {float f; uint32_t i;} u = {x};
	uint32_t a = u.i & 0x7fffffff;
	float y;

	__asm__ ("roundss $4, %1, %0" : "=x" (y) : "x" (x));
	if (a != 0 && a < 0x00800000) {
		volatile float t = x + 1.0f;	/* sacrificial: flags only */
		(void)t;
	}
	return y;
}

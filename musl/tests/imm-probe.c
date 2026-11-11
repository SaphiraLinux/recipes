/* ROUNDSD imm semantics probe: which imms implement directed
 * rounding, which follow MXCSR, which suppress inexact.
 * One function per imm (imm must be a compile-time constant). */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <fenv.h>
#include <math.h>

#define FN(IMM) static double r##IMM(double x) { double y; \
	__asm__ volatile("roundsd $" #IMM ", %1, %0" : "=x"(y) : "x"(x)); \
	return y; }
FN(0) FN(1) FN(2) FN(3) FN(4) FN(5) FN(6) FN(7)
FN(8) FN(9) FN(10) FN(11) FN(12) FN(13) FN(14) FN(15)

typedef double (*fn)(double);
static fn fns[16] = { r0,r1,r2,r3,r4,r5,r6,r7,
	r8,r9,r10,r11,r12,r13,r14,r15 };

int main(void)
{
	double vals[] = { 1.5, -1.5, 2.5, 0.1, -0.1,
		4.9406564584124654e-324, 1.0/0.0, 0.0/0.0 };
	const char *names[] = { "1.5","-1.5","2.5","0.1","-0.1",
		"denorm-min","inf","nan" };
	int nv = sizeof vals / sizeof *vals;
	int modes[] = { FE_TONEAREST, FE_DOWNWARD };
	const char *mnames[] = { "RC=near", "RC=down" };
	for (int m = 0; m < 2; m++) {
		fesetround(modes[m]);
		printf("== %s ==\n", mnames[m]);
		for (int imm = 0; imm < 16; imm++) {
			printf("imm=%02x:", imm);
			for (int i = 0; i < nv; i++) {
				feclearexcept(FE_ALL_EXCEPT);
				double y = fns[imm](vals[i]);
				int fl = fetestexcept(FE_ALL_EXCEPT);
				union { double f; uint64_t u; } u = { y };
				if (isnan(vals[i]))
					printf(" %s->nan(%x)", names[i], fl);
				else
					printf(" %s->%.1f(%x)", names[i], y, fl);
			}
			printf("\n");
		}
	}
	fesetround(FE_TONEAREST);
	return 0;
}

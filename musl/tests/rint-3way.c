/* rint 3-way: experimental arch roundsd (rint_exp) vs generic C
 * reference (rint_ref) vs MPFR truth. Linked normally against system
 * libc; the two candidates are compiled from the identical tree sources
 * used by the libc builds. NaN payloads excluded beyond sign (both
 * IEEE-quiet NaNs propagate; payload bits are implementation detail). */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#include <fenv.h>
#include <mpfr.h>

double rint_exp(double);
float rintf_exp(float);
double rint_ref(double);
float rintf_ref(float);

static long fails = 0, checked = 0, denote = 0;
static int is_snan_d(double x)
{
	union { double f; uint64_t i; } u = { x };
	return ((u.i >> 52) & 0x7ff) == 0x7ff && (u.i & 0xfffffffffffffULL) != 0 &&
		((u.i >> 51) & 1) == 0;
}

static void cmp(double x, mpfr_rnd_t mr, int mode)
{
	union { double f; uint64_t i; } e, g;
	feclearexcept(FE_ALL_EXCEPT);
	e.f = rint_exp(x);
	int fe = fetestexcept(FE_ALL_EXCEPT);
	feclearexcept(FE_ALL_EXCEPT);
	g.f = rint_ref(x);
	int fg = fetestexcept(FE_ALL_EXCEPT);
	mpfr_t m, r;
	mpfr_init2(m, 64);
	mpfr_init2(r, 64);
	mpfr_set_d(m, x, MPFR_RNDN);
	int t = mpfr_rint(r, m, mr);
	double b = mpfr_get_d(r, MPFR_RNDN);
	union { double f; uint64_t i; } u = { b };
	checked++;
	if (is_snan_d(x)) {
		if (!isnan(e.f) || !isnan(g.f) || !isnan(b)) {
			if (fails < 8)
				printf("DIFF-SNAN x=%a mode=%d\n", x, mode);
			fails++;
		}
		goto out;
	}
	/* exp vs generic reference: must match bit-for-bit incl flags
	 * (DE preservation is the point of the arch implementation). */
	if (e.i != g.i || fe != fg) {
		if (fails < 12)
			printf("DIFF exp-vs-ref x=%a mode=%d exp=%a(%x) ref=%a(%x)\n",
				x, mode, e.f, fe, g.f, fg);
		fails++;
		goto out;
	}
	/* generic reference vs MPFR truth: value + inexactness; DE bit
	 * is informational-only on both sides here. */
	{
		int vok = (g.i == u.i) || (isnan(g.f) && isnan(b));
		int iok = ((t != 0) == !!(fg & FE_INEXACT));
		if (!vok || !iok) {
			if (fails < 12)
				printf("DIFF ref-vs-mpfr x=%a mode=%d ref=%a(%x) mpfr=%a ternary=%d\n",
					x, mode, g.f, fg, b, t);
			fails++;
		} else if ((fg & 0x2) && t == 0) {
			denote++;
		}
	}
out:
	mpfr_clear(m);
	mpfr_clear(r);
}

int main(void)
{
	int modes[] = { FE_TONEAREST, FE_DOWNWARD, FE_UPWARD, FE_TOWARDZERO };
	mpfr_rnd_t mmodes[] = { MPFR_RNDN, MPFR_RNDD, MPFR_RNDU, MPFR_RNDZ };
	const char *names[] = { "nearest", "down", "up", "zero" };
	double specials[] = { 0.0, -0.0, 0.5, -0.5, 1.5, -1.5, 2.5,
		4503599627370496.0, 9007199254740992.0, 1e16,
		4.9406564584124654e-324, 2.2250738585072014e-324,
		1.7976931348623157e308, 1.0 / 0.0, -1.0 / 0.0,
		0.0 / 0.0, -0.0 / 0.0 };
	union { double f; uint64_t i; } sn = { .i = 0x7ff0000000000001ULL };
	int ns = sizeof specials / sizeof *specials;
	for (int m = 0; m < 4; m++) {
		fesetround(modes[m]);
		mpfr_set_default_rounding_mode(mmodes[m]);
		cmp(sn.f, mmodes[m], m);
		for (int i = 0; i < ns; i++)
			cmp(specials[i], mmodes[m], m);
		union { double f; uint64_t i; } u;
		for (int k = 0; k < 20000; k++) {
			uint64_t v = (uint64_t)k * 7919;
			u.i = v & 0xffffffffffffffffULL;
			if (((u.i >> 52) & 0x7ff) != 0x7ff)
				cmp(u.f, mmodes[m], m);
			u.i = 0x3ff0000000000000ULL | (v & 0xfffffffffffffULL);
			cmp(u.f, mmodes[m], m);
			u.i = 0x3ff8000000000000ULL | ((v * 3) & 0xfffffffffffffULL);
			cmp(u.f, mmodes[m], m);
		}
		uint64_t s = 0x123456789abcdefULL + m;
		for (int k = 0; k < 200000; k++) {
			s = s * 6364136223846793005ULL + 1449691640888963407ULL;
			u.i = s & 0x7fffffffffffffffULL;
			if (((u.i >> 52) & 0x7ff) == 0x7ff)
				continue;
			cmp(u.f, mmodes[m], m);
		}
		printf("mode %-7s fails=%ld denote=%ld\n", names[m], fails, denote);
	}
	mpfr_free_cache();
	printf("TOTAL checked=%ld fails=%ld denormal-bit-only=%ld\n", checked, fails, denote);
	return fails != 0;
}

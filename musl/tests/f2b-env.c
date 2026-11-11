/* F2b environment behaviour: sticky flags, DAZ/FTZ, MXCSR
 * preservation, fork-isolated unmasked-exception traps. */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#include <fenv.h>
#include <float.h>
#include <sys/wait.h>
#include <unistd.h>
#include <stdlib.h>

static double c_floor(double x)
{ double y; __asm__ volatile("roundsd $9, %1, %0" : "=x"(y) : "x"(x)); return y; }
static double c_trunc(double x)
{ double y; __asm__ volatile("roundsd $11, %1, %0" : "=x"(y) : "x"(x)); return y; }
static double c_nearby(double x)
{ double y; __asm__ volatile("roundsd $12, %1, %0" : "=x"(y) : "x"(x)); return y; }
static float c_floorf(float x)
{ float y; __asm__ volatile("roundss $9, %1, %0" : "=x"(y) : "x"(x)); return y; }

static unsigned get_mxcsr(void)
{ unsigned m; __asm__ volatile("stmxcsr %0" : "=m"(m)); return m; }
static void set_mxcsr(unsigned m)
{ __asm__ volatile("ldmxcsr %0" :: "m"(m)); }

/* 1. sticky isolation: preset all-but-one-bit, call, report final flags */
static void sticky(const char *fn, double (*g)(double), double (*c)(double),
		   double x, unsigned preset)
{
	int gf, cf;
	unsigned before, after;
	set_mxcsr((get_mxcsr() & ~0x3fU) | (preset & 0x3fU));
	before = get_mxcsr();
	feclearexcept(0); /* no-op guard: preset via mxcsr, verify readback */
	gf = 0; { volatile double r = g(x); (void)r; gf = fetestexcept(FE_ALL_EXCEPT); }
	unsigned gfmx = get_mxcsr() & 0x3fU;
	set_mxcsr((before & ~0x3fU) | (preset & 0x3fU));
	cf = 0; { volatile double r = c(x); (void)r; cf = fetestexcept(FE_ALL_EXCEPT); }
	unsigned cfmx = get_mxcsr() & 0x3fU;
	after = get_mxcsr();
	printf("STICKY %-6s x=%a preset=%02x gen-flags=%02x cand-flags=%02x %s\n",
	       fn, x, preset & 0x3fU, gfmx, cfmx,
	       (gfmx == cfmx) ? "same" : "DIFF");
	(void)gf; (void)cf; (void)after;
}

static void stickyf(const char *fn, float (*g)(float), float (*c)(float),
		    float x, unsigned preset)
{
	set_mxcsr((get_mxcsr() & ~0x3fU) | (preset & 0x3fU));
	{ volatile float r = g(x); (void)r; }
	unsigned gfmx = get_mxcsr() & 0x3fU;
	set_mxcsr((get_mxcsr() & ~0x3fU) | (preset & 0x3fU));
	{ volatile float r = c(x); (void)r; }
	unsigned cfmx = get_mxcsr() & 0x3fU;
	printf("STICKY %-6s x=%a preset=%02x gen-flags=%02x cand-flags=%02x %s\n",
	       fn, x, preset & 0x3fU, gfmx, cfmx,
	       (gfmx == cfmx) ? "same" : "DIFF");
}

/* 2. DAZ/FTZ combos on subnormal + normal-fractional inputs */
static void dazftz(void)
{
	unsigned combos[] = { 0x0000, 0x0040, 0x8000, 0x8040 };
	const char *cn[] = { "none", "DAZ", "FTZ", "DAZ+FTZ" };
	double vals[] = { 0x1p-1074, -0x1p-1074, 0x1.fffffffffffffp-1023,
		DBL_MIN, 0.1, 2.5 };
	for (int k = 0; k < 4; k++) {
		unsigned base = (get_mxcsr() & ~(0x8040U | 0x3fU)) | combos[k];
		for (unsigned i = 0; i < sizeof vals / sizeof *vals; i++) {
			set_mxcsr(base);
			volatile double rg = floor(vals[i]);
			(void)rg;
			unsigned fg = get_mxcsr() & 0x3fU;
			set_mxcsr(base);
			volatile double rc = c_floor(vals[i]);
			(void)rc;
			unsigned fc = get_mxcsr() & 0x3fU;
			set_mxcsr(base & ~0x8040U);
			printf("DAZFTZ %-7s x=%a gen=%02x cand=%02x %s\n",
			       cn[k], vals[i], fg, fc,
			       (fg == fc) ? "same" : "DIFF");
		}
	}
	set_mxcsr(get_mxcsr() & ~0x8040U);
}

/* 3. fork-isolated unmasked traps: child returns 42 on SIGFPE */
/* Shared with parent via exit status only. */
typedef double (*dfn)(double);
static int trapped(dfn f, double x, unsigned unmask_bit)
{
	pid_t p = fork();
	if (p == 0) {
		unsigned m = get_mxcsr() & ~unmask_bit;
		set_mxcsr(m);
		feclearexcept(FE_ALL_EXCEPT);
		volatile double r = f(x);
		(void)r;
		_exit(0);
	}
	int st = 0;
	waitpid(p, &st, 0);
	if (WIFSIGNALED(st) && WTERMSIG(st) == SIGFPE) return 1;
	return 0;
}

int main(void)
{
	fesetround(FE_TONEAREST);
	printf("--- sticky: exact input, all-but-inexact preset ---\n");
	sticky("floor", floor, c_floor, 2.0, 0x1f);
	sticky("trunc", trunc, c_trunc, 2.0, 0x1f);
	sticky("nearby", nearbyint, c_nearby, 2.0, 0x1f);
	printf("--- sticky: fractional input, all-but-inexact preset ---\n");
	sticky("floor", floor, c_floor, 0.1, 0x1f);
	sticky("trunc", trunc, c_trunc, 0.1, 0x1f);
	sticky("nearby", nearbyint, c_nearby, 0.1, 0x1f);
	printf("--- sticky: subnormal input, all-but-DE preset ---\n");
	sticky("floor", floor, c_floor, 0x1p-1074, 0x3d);
	sticky("nearby", nearbyint, c_nearby, 0x1p-1074, 0x3d);
	printf("--- sticky float: fractional, all-but-inexact ---\n");
	stickyf("floorf", floorf, c_floorf, 0.1f, 0x1f);
	printf("--- DAZ/FTZ: floor generic vs candidate ---\n");
	dazftz();
	printf("--- unmasked inexact (PM) + 0.1: trap? ---\n");
	{
		struct { const char *n; dfn g; dfn c; } t[] = {
			{ "floor", floor, c_floor }, { "trunc", trunc, c_trunc },
			{ "nearbyint", nearbyint, c_nearby },
		};
		for (unsigned i = 0; i < sizeof t / sizeof *t; i++) {
			int tg = trapped(t[i].g, 0.1, 0x1000);
			int tc = trapped(t[i].c, 0.1, 0x1000);
			printf("UNMASKED-PE %-9s gen=%s cand=%s %s\n", t[i].n,
			       tg ? "TRAP" : "quiet", tc ? "TRAP" : "quiet",
			       (tg == tc) ? "same" : "DIFF");
		}
	}
	printf("--- unmasked invalid (IM) + sNaN: trap? ---\n");
	{
		union { double f; uint64_t i; } SN = { .i = 0x7FF0000000000001ULL };
		int tg = trapped(floor, SN.f, 0x80);
		int tc = trapped(c_floor, SN.f, 0x80);
		printf("UNMASKED-IM sNaN gen=%s cand=%s %s\n",
		       tg ? "TRAP" : "quiet", tc ? "TRAP" : "quiet",
		       (tg == tc) ? "same" : "DIFF");
		int tg2 = trapped(nearbyint, SN.f, 0x80);
		int tc2 = trapped(c_nearby, SN.f, 0x80);
		printf("UNMASKED-IM sNaN nearby gen=%s cand=%s %s\n",
		       tg2 ? "TRAP" : "quiet", tc2 ? "TRAP" : "quiet",
		       (tg2 == tc2) ? "same" : "DIFF");
	}
	printf("--- MXCSR preservation (RC/masks untouched) ---\n");
	{
		unsigned before = get_mxcsr();
		volatile double a = c_floor(0.1), b = c_trunc(-2.5),
				c = c_nearby(0x1p-1074);
		(void)a; (void)b; (void)c;
		unsigned after = get_mxcsr();
		printf("MXCSR before=%08x after=%08x %s\n", before, after,
		       ((before & ~0x3fU) == (after & ~0x3fU)) ? "preserved" : "CLOBBERED");
	}
	return 0;
}

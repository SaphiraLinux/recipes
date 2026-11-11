/* F2 floor-family differential: published musl r7 (live libc calls)
 * vs SSE4.1 suppress-imm candidates and the generic-nearbyint +
 * arch-rint combo actually shipped by sinew (generic nearbyint
 * source bound to arch rint at compile time, mirroring libc).
 * Documents value + flag differences; never gates. */
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

/* ---- candidates under test (proposed, NOT committed to any recipe) ---- */
static double c_floor(double x)
{ double y; __asm__ volatile("roundsd $9, %1, %0" : "=x"(y) : "x"(x)); return y; }
static double c_ceil(double x)
{ double y; __asm__ volatile("roundsd $10, %1, %0" : "=x"(y) : "x"(x)); return y; }
static double c_trunc(double x)
{ double y; __asm__ volatile("roundsd $11, %1, %0" : "=x"(y) : "x"(x)); return y; }
static double c_nearby(double x)
{ double y; __asm__ volatile("roundsd $12, %1, %0" : "=x"(y) : "x"(x)); return y; }
static float c_floorf(float x)
{ float y; __asm__ volatile("roundss $9, %1, %0" : "=x"(y) : "x"(x)); return y; }
static float c_ceilf(float x)
{ float y; __asm__ volatile("roundss $10, %1, %0" : "=x"(y) : "x"(x)); return y; }
static float c_truncf(float x)
{ float y; __asm__ volatile("roundss $11, %1, %0" : "=x"(y) : "x"(x)); return y; }
static float c_nearbyf(float x)
{ float y; __asm__ volatile("roundss $12, %1, %0" : "=x"(y) : "x"(x)); return y; }

/* combo mirrors sinew libc: generic nearbyint source + arch rint */
double nearby_combo(double);
float nearbyf_combo(float);

static unsigned get_mxcsr(void)
{ unsigned m; __asm__ volatile("stmxcsr %0" : "=m"(m)); return m; }
static void set_mxcsr(unsigned m)
{ __asm__ volatile("ldmxcsr %0" :: "m"(m)); }

static long ndiff_val = 0, ndiff_flag = 0, checked = 0;
static long f_val[10] = {0}, f_flag[10] = {0};
static int fn_index(const char *fn)
{
	if (!strcmp(fn, "floor")) return 0;
	if (!strcmp(fn, "ceil")) return 1;
	if (!strcmp(fn, "trunc")) return 2;
	if (!strcmp(fn, "nearbyint")) return 3;
	if (!strcmp(fn, "nearbyint-combo")) return 4;
	if (!strcmp(fn, "floorf")) return 5;
	if (!strcmp(fn, "ceilf")) return 6;
	if (!strcmp(fn, "truncf")) return 7;
	if (!strcmp(fn, "nearbyintf")) return 8;
	if (!strcmp(fn, "nearbyintf-combo")) return 9;
	return -1;
}
static int is_snan_d(double x)
{ union { double f; uint64_t i; } u = { x };
  return ((u.i >> 52) & 0x7ff) == 0x7ff && (u.i & 0xfffffffffffffULL) &&
	 ((u.i >> 51) & 1) == 0; }

static void cmpd(const char *fn, double x, int mode,
		 double (*g)(double), double (*c)(double))
{
	union { double f; uint64_t i; } gv, cv;
	int gf, cf;
	feclearexcept(FE_ALL_EXCEPT); gv.f = g(x); gf = fetestexcept(FE_ALL_EXCEPT);
	feclearexcept(FE_ALL_EXCEPT); cv.f = c(x); cf = fetestexcept(FE_ALL_EXCEPT);
	checked++;
	int bothnan = isnan(gv.f) && isnan(cv.f);
	int vok = bothnan ? ((gv.i >> 63) == (cv.i >> 63)) : (gv.i == cv.i);
	if (!vok || gf != cf) {
		if (bothnan && vok && gf == cf) return;
		if (ndiff_val + ndiff_flag < 500) {
			if (bothnan)
				printf("DIFF %s x=bits%lx mode=%d gen=.(%lx)(%x) cand=.(%lx)(%x)%s\n",
				       fn, (unsigned long)((union{double f;uint64_t i;}){x}.i),
				       mode, (unsigned long)gv.i, gf,
				       (unsigned long)cv.i, cf,
				       is_snan_d(x) ? " [sNaN-in]" : " [qNaN-in]");
			else
				printf("DIFF %s x=%a mode=%d gen=%a(%x) cand=%a(%x)\n",
				       fn, x, mode, gv.f, gf, cv.f, cf);
		}
		if (!vok) ndiff_val++;
		if (gf != cf) ndiff_flag++;
		int fi = fn_index(fn);
		if (fi >= 0) {
			if (!vok) f_val[fi]++;
			if (gf != cf) f_flag[fi]++;
		}
	}
}

static void cmpf(const char *fn, float x, int mode,
		 float (*g)(float), float (*c)(float))
{
	union { float f; uint32_t i; } gv, cv;
	int gf, cf;
	feclearexcept(FE_ALL_EXCEPT); gv.f = g(x); gf = fetestexcept(FE_ALL_EXCEPT);
	feclearexcept(FE_ALL_EXCEPT); cv.f = c(x); cf = fetestexcept(FE_ALL_EXCEPT);
	checked++;
	int bothnan = isnan(gv.f) && isnan(cv.f);
	int vok = bothnan ? ((gv.i >> 31) == (cv.i >> 31)) : (gv.i == cv.i);
	if (!vok || gf != cf) {
		if (bothnan && vok && gf == cf) return;
		if (ndiff_val + ndiff_flag < 40)
			printf("DIFF %s x=%a mode=%d gen=%a(%x) cand=%a(%x)\n",
			       fn, x, mode, gv.f, gf, cv.f, cf);
		if (!vok) ndiff_val++;
		if (gf != cf) ndiff_flag++;
		int fif = fn_index(fn);
		if (fif >= 0) {
			if (!vok) f_val[fif]++;
			if (gf != cf) f_flag[fif]++;
		}
	}
}

int main(void)
{
	int modes[] = { FE_TONEAREST, FE_DOWNWARD, FE_UPWARD, FE_TOWARDZERO };
	union { double f; uint64_t i; } SNAN = { .i = 0x7FF0000000000001ULL };
	union { double f; uint64_t i; } QNAN = { .i = 0x7FF8000000000000ULL };
	double dv[] = { 0.0, -0.0, 1.0, -1.0, 0.5, -0.5, 1.5, -1.5, 2.5, -2.5,
		0.1, -0.1, 0.49999999999999994, 4503599627370496.0,
		4503599627370497.0, 1e16, -1e16, 1e300, DBL_MIN, DBL_MAX,
		0x1p-1074, -0x1p-1074, 0x1.fffffffffffffp-1023,
		-0x1.fffffffffffffp-1023, 1.0/0.0, -1.0/0.0,
		QNAN.f, SNAN.f };
	int ndv = sizeof dv / sizeof *dv;
	struct { const char *n; double (*g)(double); double (*c)(double); } de[] = {
		{ "floor", floor, c_floor }, { "ceil", ceil, c_ceil },
		{ "trunc", trunc, c_trunc }, { "nearbyint", nearbyint, c_nearby },
		{ "nearbyint-combo", nearbyint, nearby_combo },
	};
	union { float f; uint32_t i; } FS = { .i = 0x7F800001U };
	union { float f; uint32_t i; } FQ = { .i = 0x7FC00000U };
	float fv[] = { 0.f, -0.f, 1.5f, -1.5f, 2.5f, -2.5f, 0.1f, -0.1f,
		8388608.f, 8388609.f, 1e10f, FLT_MIN, FLT_MAX,
		0x1p-149f, -0x1p-149f, 0x1.fffffep-127f, -0x1.fffffep-127f,
		1.f/0.f, -1.f/0.f, FQ.f, FS.f };
	int nfv = sizeof fv / sizeof *fv;
	struct { const char *n; float (*g)(float); float (*c)(float); } fe[] = {
		{ "floorf", floorf, c_floorf }, { "ceilf", ceilf, c_ceilf },
		{ "truncf", truncf, c_truncf }, { "nearbyintf", nearbyintf, c_nearbyf },
		{ "nearbyintf-combo", nearbyintf, nearbyf_combo },
	};
	for (int m = 0; m < 4; m++) {
		fesetround(modes[m]);
		for (unsigned i = 0; i < sizeof de / sizeof *de; i++)
			for (int k = 0; k < ndv; k++)
				cmpd(de[i].n, dv[k], m, de[i].g, de[i].c);
		for (unsigned i = 0; i < sizeof fe / sizeof *fe; i++)
			for (int k = 0; k < nfv; k++)
				cmpf(fe[i].n, fv[k], m, fe[i].g, fe[i].c);
		printf("mode %d: value-diffs=%ld flag-diffs=%ld\n",
		       m, ndiff_val, ndiff_flag);
	}
	fesetround(FE_TONEAREST);
	printf("SWEEP checked=%ld value-diffs=%ld flag-diffs=%ld\n",
	       checked, ndiff_val, ndiff_flag);
	{
		const char *names[10] = { "floor", "ceil", "trunc", "nearbyint",
			"nearbyint-combo", "floorf", "ceilf", "truncf",
			"nearbyintf", "nearbyintf-combo" };
		for (int i = 0; i < 10; i++)
			printf("FUNC %-18s value-diffs=%ld flag-diffs=%ld\n",
			       names[i], f_val[i], f_flag[i]);
	}
	return 0;
}

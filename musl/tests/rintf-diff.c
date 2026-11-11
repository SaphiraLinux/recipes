#define _GNU_SOURCE
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#include <fenv.h>
extern float rintf_exp(float);
extern float rintf_ref(float);
static long fails = 0, n = 0;
static void cmp(float x, int mode) {
    union { float f; uint32_t i; } a, b;
    feclearexcept(FE_ALL_EXCEPT); a.f = rintf_exp(x); int fa = fetestexcept(FE_ALL_EXCEPT);
    feclearexcept(FE_ALL_EXCEPT); b.f = rintf_ref(x); int fb = fetestexcept(FE_ALL_EXCEPT);
    n++;
    if (a.i != b.i || fa != fb) { if (fails < 10) printf("DIFF x=%a mode=%d exp=%a(%x) ref=%a(%x)\n", x, mode, a.f, fa, b.f, fb); fails++; }
}
int main(void) {
    int modes[] = { FE_TONEAREST, FE_DOWNWARD, FE_UPWARD, FE_TOWARDZERO };
    float vals[] = {0.f, -0.f, 0.5f, 1.5f, 2.5f, -2.5f, 8388609.f, 1e10f, 1.4e-45f, 1.17549435e-38f, 3.40282347e38f, 1.f/0, -1.f/0, 0.f/0};
    for (int m = 0; m < 4; m++) { fesetround(modes[m]);
        for (unsigned i = 0; i < sizeof vals / sizeof *vals; i++) cmp(vals[i], m);
        union { float f; uint32_t i; } u;
        for (int k = 0; k < 20000; k++) { uint32_t v = (uint32_t)k * 7919u;
            u.i = v & 0xffffffffu; if (((u.i >> 23) & 0xff) != 0xff) cmp(u.f, m);
            u.i = 0x3f800000u | (v & 0x7fffffu); cmp(u.f, m); }
        uint32_t s = 0x12345678 + m;
        for (int k = 0; k < 200000; k++) { s = s * 1664525u + 1013904223u; u.i = s;
            if (((u.i >> 23) & 0xff) == 0xff) continue; cmp(u.f, m); }
        printf("mode %d fails=%ld\n", m, fails); }
    fesetround(FE_TONEAREST);
    printf("TOTAL n=%ld fails=%ld\n", n, fails);
    return fails != 0;
}

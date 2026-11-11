/* F2 candidate shapes (proposed, scratch-only): one suppress-imm
 * per function, no flag dance. Disassembly + perf source. */
#include <math.h>
double f2_floor(double x)
{ double y; __asm__ volatile("roundsd $9, %1, %0" : "=x"(y) : "x"(x)); return y; }
double f2_ceil(double x)
{ double y; __asm__ volatile("roundsd $10, %1, %0" : "=x"(y) : "x"(x)); return y; }
double f2_trunc(double x)
{ double y; __asm__ volatile("roundsd $11, %1, %0" : "=x"(y) : "x"(x)); return y; }
double f2_nearbyint(double x)
{ double y; __asm__ volatile("roundsd $12, %1, %0" : "=x"(y) : "x"(x)); return y; }
float f2_floorf(float x)
{ float y; __asm__ volatile("roundss $9, %1, %0" : "=x"(y) : "x"(x)); return y; }
float f2_ceilf(float x)
{ float y; __asm__ volatile("roundss $10, %1, %0" : "=x"(y) : "x"(x)); return y; }
float f2_truncf(float x)
{ float y; __asm__ volatile("roundss $11, %1, %0" : "=x"(y) : "x"(x)); return y; }
float f2_nearbyintf(float x)
{ float y; __asm__ volatile("roundss $12, %1, %0" : "=x"(y) : "x"(x)); return y; }

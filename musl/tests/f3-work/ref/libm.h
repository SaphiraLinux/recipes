/* Shim for compiling upstream musl generic math files standalone. */
#include <float.h>
#include <math.h>
#include <stdint.h>
#define FORCE_EVAL(x) do { \
	if (sizeof(x) == sizeof(float)) { volatile float __x; __x = (x); (void)__x; } \
	else if (sizeof(x) == sizeof(double)) { volatile double __x; __x = (x); (void)__x; } \
	else { volatile long double __x; __x = (x); (void)__x; } \
} while(0)

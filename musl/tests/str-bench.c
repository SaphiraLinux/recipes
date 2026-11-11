/* String-search baseline: current musl impls across realistic shapes.
 * Dynamic (live libc). Reports ns/call (min of runs). */
#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <stdint.h>
#include <time.h>

static double now_ns(void)
{ struct timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (double)t.tv_sec * 1e9 + (double)t.tv_nsec; }

#define BENCH(name, iters, stmt) do { \
	double best = 1e18; \
	for (int k = 0; k < 5; k++) { \
		double t0 = now_ns(); \
		for (int i = 0; i < iters; i++) { stmt; } \
		double dt = now_ns() - t0; \
		if (dt < best) best = dt; \
	} \
	printf("%-28s %8.1f ns/call\n", name, best / (iters)); \
	} while (0)

int main(void)
{
	volatile int sink = 0;
	static char h[65536 + 64], h2[65536 + 64];
	for (int i = 0; i < 65536 + 64; i++) { h[i] = (char)(33 + (i % 90)); h2[i] = h[i]; }
	h[65535] = 0; h2[65535] = 0;
	/* strchr shapes */
	BENCH("strchr n=16 early", 200000, sink += (strchr(h, h[1]) != 0));
	BENCH("strchr n=16 late", 200000, sink += (strchr(h, h[14]) != 0));
	BENCH("strchr n=16 absent", 200000, sink += (strchr(h, 127) != 0));
	BENCH("strchr n=64 late", 200000, sink += (strchr(h, h[60]) != 0));
	BENCH("strchr n=256 late", 100000, sink += (strchr(h, h[250]) != 0));
	BENCH("strchr n=4k late", 20000, sink += (strchr(h, h[4000]) != 0));
	/* strnlen shapes (NUL at end of region) */
	BENCH("strnlen n=16", 200000, sink += (int)strnlen(h, 16));
	BENCH("strnlen n=64", 200000, sink += (int)strnlen(h, 64));
	BENCH("strnlen n=256", 100000, sink += (int)strnlen(h, 256));
	BENCH("strnlen n=4k", 20000, sink += (int)strnlen(h, 4096));
	/* strncmp: equal + differ positions */
	BENCH("strncmp eq n=16", 200000, sink += strncmp(h, h2, 16));
	BENCH("strncmp eq n=64", 200000, sink += strncmp(h, h2, 64));
	BENCH("strncmp eq n=256", 100000, sink += strncmp(h, h2, 256));
	BENCH("strncmp eq n=4k", 20000, sink += strncmp(h, h2, 4096));
	BENCH("strncmp diff@0 n=64", 200000, { h2[0] ^= 1; sink += strncmp(h, h2, 64); h2[0] ^= 1; });
	BENCH("strncmp diff@end n=64", 200000, { h2[63] ^= 1; sink += strncmp(h, h2, 64); h2[63] ^= 1; });
	BENCH("strncmp diff@end n=4k", 20000, { h2[4095] ^= 1; sink += strncmp(h, h2, 4096); h2[4095] ^= 1; });
	/* memcmp */
	BENCH("memcmp eq n=16", 200000, sink += memcmp(h, h2, 16));
	BENCH("memcmp eq n=64", 200000, sink += memcmp(h, h2, 64));
	BENCH("memcmp eq n=4k", 20000, sink += memcmp(h, h2, 4096));
	BENCH("memcmp diff@end n=4k", 20000, { h2[4095] ^= 1; sink += memcmp(h, h2, 4096); h2[4095] ^= 1; });
	/* memchr */
	BENCH("memchr early n=64", 200000, sink += (memchr(h, h[1], 64) != 0));
	BENCH("memchr late n=64", 200000, sink += (memchr(h, h[60], 64) != 0));
	BENCH("memchr absent n=64", 200000, sink += (memchr(h, 127, 64) != 0));
	BENCH("memchr late n=4k", 20000, sink += (memchr(h, h[4000], 4096) != 0));
	BENCH("memchr absent n=4k", 20000, sink += (memchr(h, 127, 4096) != 0));
	BENCH("memchr absent n=64k", 2000, sink += (memchr(h, 127, 65536) != 0));
	(void)sink;
	return 0;
}

/* t8-steps: crash bisection probe for the baseline t8-misc segfault.
 * Prints a marker after every operation; the last marker before the
 * crash identifies the faulty call on the unpatched tree. */
#define _GNU_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <string.h>

int main(void)
{
	char b[4] = { 0 };
	FILE *f = fmemopen(b, sizeof b, "w");
	printf("step1 fmemopen-ok\n");
	fflush(stdout);
	size_t w = fwrite("0123456789", 1, 10, f);
	printf("step2 fwrite=%zu ferror=%d\n", w, ferror(f));
	fflush(stdout);
	fclose(f);
	printf("step3 fclose1-ok\n");
	fflush(stdout);
	char c[8];
	memset(c, 'x', sizeof c);
	f = fmemopen(c, sizeof c, "w");
	printf("step4 fmemopen2-ok\n");
	fflush(stdout);
	fwrite("ABCDEFG", 1, 7, f);
	printf("step5 fwrite2-ok\n");
	fflush(stdout);
	fclose(f);
	printf("step6 fclose2-ok bytes=");
	for (int i = 0; i < 8; i++)
		printf("%02x", (unsigned char)c[i]);
	printf("\n");
	return 0;
}

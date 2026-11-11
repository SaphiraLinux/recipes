/* t8a: fmemopen + fseeko (upstream 9086784b, bb4b4102, 30cc6422). */
#define _GNU_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <string.h>
#include <errno.h>

int main(void)
{
	char b[4] = { 0 };
	FILE *f = fmemopen(b, sizeof b, "w");
	size_t w = fwrite("0123456789", 1, 10, f);
	int e0 = ferror(f);
	errno = 0;
	int fr = fflush(f);
	int e1 = ferror(f);
	int ee = errno;
	printf("fmemopen-enospc: wrote=%zu pre_err=%d fflush=%d post_err=%d errno=%d buf=%02x%02x%02x%02x\n",
		w, e0, fr, e1, ee,
		(unsigned char)b[0], (unsigned char)b[1],
		(unsigned char)b[2], (unsigned char)b[3]);
	fclose(f);

	char c[8];
	memset(c, 'x', sizeof c);
	f = fmemopen(c, sizeof c, "w");
	fwrite("ABCDEFGH", 1, 8, f);
	fclose(f);
	printf("fmemopen-clobber: dump=");
	for (int i = 0; i < 8; i++)
		printf("%02x", (unsigned char)c[i]);
	printf(" (correct ends 48, buggy ends 00)\n");

	f = tmpfile();
	errno = 0;
	int r = fseeko(f, (off_t)0x8000000000000000LL, SEEK_CUR);
	printf("fseeko-LLONG_MIN: r=%d errno=%d (correct -1 EOVERFLOW=75)\n",
		r, errno);
	fclose(f);
	return 0;
}

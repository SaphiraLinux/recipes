/* t12: t8b bisection — one marker per op to locate the baseline crash. */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include <stdint.h>
#include <mntent.h>

#define MARK(m) do { printf("mark %s\n", m); fflush(stdout); } while (0)

int main(void)
{
	FILE *f = tmpfile();
	MARK("tmpfile");
	for (int i = 0; i < 3000; i++)
		fputs("0123456789abcdef", f);
	fputs(" /mnt/gpfs gpfs rw 0 0\n", f);
	MARK("written");
	rewind(f);
	MARK("rewound");
	struct mntent *m = getmntent(f);
	MARK("getmntent");
	printf("mntent: %s\n", m ? m->mnt_dir : "(null)");
	fflush(stdout);
	fclose(f);
	MARK("fclose");
	void *p = wcsrchr(L"hello world", L'z');
	MARK("wcsrchr-absent");
	printf("wcsrchr: %p\n", p);
	fflush(stdout);
	void *q = 0;
	int r = posix_memalign(&q, 1U << 24, 16);
	MARK("memalign");
	printf("memalign: r=%d\n", r);
	free(q);
	MARK("done");
	return 0;
}

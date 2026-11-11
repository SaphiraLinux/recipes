/* t8b: mntent/wcsrchr/malloc/strerror/catgets/clock/cpuid
 * (upstream ba6961dd, 15a1155e, e9ac48d2, bf96b52a, c5e2f7e7, a2985317,
 * cb0cdc2e, aeeb7dd4). */
#define _GNU_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include <stdint.h>
#include <time.h>
#include <sched.h>
#include <mntent.h>
#include <netdb.h>
#include <regex.h>
#include <nl_types.h>

int main(void)
{
	FILE *f = tmpfile();
	for (int i = 0; i < 3000; i++)
		fputs("0123456789abcdef", f);
	fputs(" /mnt/gpfs gpfs rw 0 0\n", f);
	rewind(f);
	struct mntent *m = getmntent(f);
	printf("mntent-longline: %s (correct /mnt/gpfs)\n",
		m ? m->mnt_dir : "(null)");
	fclose(f);

	printf("wcsrchr-absent: %p (correct nil)\n",
#ifndef SKIP_WCSRCHR
		(void *)wcsrchr(L"hello world", L'z'));
	printf("wcsrchr-found: %ls\n", wcsrchr(L"hello world", L'o'));
#else
		(void *)0);
	printf("wcsrchr-found: skipped\n");
#endif

	void *p = 0;
	int r = posix_memalign(&p, 1U << 24, 16);
	printf("memalign-huge: r=%d aligned=%d\n", r,
		p ? (int)(((uintptr_t)p & ((1U << 24) - 1)) == 0) : -1);
	free(p);

	printf("gai_strerror-INT_MAX: %s\n", gai_strerror(2147483647));
	printf("hstrerror-INT_MIN: %s\n", hstrerror(-2147483647 - 1));
	char eb[128];
	printf("regerror-INT_MIN: %s\n",
		regerror(-2147483647 - 1, 0, eb, sizeof eb) ? eb : "?");

	nl_catd d = (nl_catd)-1;
	printf("catgets-neg1: %s (correct dflt)\n",
		catgets(d, 1, 1, "dflt"));

	struct timespec ts = { 0, 1000000 };
	printf("clock_nanosleep: %d (correct 0)\n",
		clock_nanosleep(CLOCK_REALTIME, 0, &ts, 0));

	cpu_set_t s;
	CPU_ZERO(&s);
	printf("cpu_isset: %d (correct 0)\n", CPU_ISSET(3, &s));
	return 0;
}

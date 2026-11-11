/* t8b-marks: full-marker crash locator in the t8b binary layout. */
#define _GNU_SOURCE
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
	struct mntent *m = getmntent(f);
	MARK("getmntent");
	printf("mntent: %s\n", m ? m->mnt_dir : "(null)");
	fflush(stdout);
	fclose(f);
	MARK("fclose");
	void *w = wcsrchr(L"hello world", L'z');
	MARK("wcsrchr-absent");
	printf("wcsrchr: %p %ls\n", w, wcsrchr(L"hello world", L'o'));
	fflush(stdout);
	void *p = 0;
	int r = posix_memalign(&p, 1U << 24, 16);
	MARK("memalign");
	printf("memalign: r=%d\n", r);
	fflush(stdout);
	free(p);
	MARK("free");
	printf("gai: %s\n", gai_strerror(2147483647));
	MARK("gai_strerror");
	printf("hstr: %s\n", hstrerror(-2147483647 - 1));
	MARK("hstrerror");
	char eb[128];
	printf("regerr: %s\n",
		regerror(-2147483647 - 1, 0, eb, sizeof eb) ? eb : "?");
	MARK("regerror");
	nl_catd d = (nl_catd)-1;
	printf("catgets: %s\n", catgets(d, 1, 1, "dflt"));
	MARK("catgets");
	struct timespec ts = { 0, 1000000 };
	printf("nanosleep: %d\n", clock_nanosleep(CLOCK_REALTIME, 0, &ts, 0));
	MARK("clock");
	cpu_set_t s;
	CPU_ZERO(&s);
	printf("cpuset: %d\n", CPU_ISSET(3, &s));
	MARK("done");
	return 0;
}

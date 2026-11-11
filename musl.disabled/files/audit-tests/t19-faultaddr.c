/* t19: t8b-misc sequence with a SIGSEGV handler reporting the fault
 * address plus key addresses (string literal, brk). Identifies whether
 * the t8b-layout baseline crash is an OOB read of s-1, heap-metadata
 * corruption, or another wild access. Patched tree must run clean. */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <wchar.h>
#include <stdint.h>
#include <time.h>
#include <sched.h>
#include <mntent.h>
#include <netdb.h>
#include <regex.h>
#include <nl_types.h>
#include <unistd.h>

static void onsegv(int sig, siginfo_t *si, void *ctx)
{
	(void)sig;
	(void)ctx;
	char buf[256];
	int n = snprintf(buf, sizeof buf, "SEGFAULT si_addr=%p\n",
		si->si_addr);
	write(STDOUT_FILENO, buf, (size_t)n);
	_exit(139);
}

int main(void)
{
	struct sigaction sa;
	memset(&sa, 0, sizeof sa);
	sa.sa_sigaction = onsegv;
	sa.sa_flags = SA_SIGINFO | SA_RESETHAND;
	sigaction(SIGSEGV, &sa, 0);

	printf("addrs: lit=%p brk=%p\n", (const void *)L"hello world", sbrk(0));
	fflush(stdout);
	FILE *f = tmpfile();
	for (int i = 0; i < 3000; i++)
		fputs("0123456789abcdef", f);
	fputs(" /mnt/gpfs gpfs rw 0 0\n", f);
	rewind(f);
	struct mntent *m = getmntent(f);
	printf("mntent: %s\n", m ? m->mnt_dir : "(null)");
	fflush(stdout);
	fclose(f);
	printf("wcsrchr-absent: %p\n",
		(void *)wcsrchr(L"hello world", L'z'));
	fflush(stdout);
	printf("wcsrchr-found: %ls\n", wcsrchr(L"hello world", L'o'));
	fflush(stdout);
	void *p = 0;
	int r = posix_memalign(&p, 1U << 24, 16);
	printf("memalign: r=%d\n", r);
	fflush(stdout);
	free(p);
	printf("gai: %s\n", gai_strerror(2147483647));
	fflush(stdout);
	printf("hstr: %s\n", hstrerror(-2147483647 - 1));
	fflush(stdout);
	char eb[128];
	size_t n = regerror(-2147483647 - 1, 0, eb, sizeof eb);
	printf("regerr: n=%zu %s\n", n, eb);
	fflush(stdout);
	nl_catd d = (nl_catd)-1;
	printf("catgets: %s\n", catgets(d, 1, 1, "dflt"));
	fflush(stdout);
	struct timespec ts = { 0, 1000000 };
	printf("nanosleep: %d\n", clock_nanosleep(CLOCK_REALTIME, 0, &ts, 0));
	fflush(stdout);
	cpu_set_t s;
	CPU_ZERO(&s);
	printf("cpuset: %d done\n", CPU_ISSET(3, &s));
	return 0;
}

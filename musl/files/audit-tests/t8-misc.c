/* t8: misc corrections (upstream 9086784b, bb4b4102, 30cc6422, ba6961dd,
 * 15a1155e, e9ac48d2, bf96b52a, c5e2f7e7, a2985317, cb0cdc2e, 235f7289,
 * 331cf270, 38e04447, aeeb7dd4, 67219f01, f21a9653 smoke).
 */
#define _GNU_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <wchar.h>
#include <stdint.h>
#include <time.h>
#include <sched.h>
#include <mntent.h>
#include <netdb.h>
#include <regex.h>
#include <nl_types.h>
#include <iconv.h>
#include <wordexp.h>

static void t_fmemopen(void)
{
	char b[4] = { 0 };
	FILE *f = fmemopen(b, sizeof b, "w");
	size_t w = fwrite("0123456789", 1, 10, f);
	int e = ferror(f);
	printf("fmemopen-enospc: wrote=%zu ferror=%d (correct short+nonzero)\n",
		w, e);
	fclose(f);

	char c[8];
	memset(c, 'x', sizeof c);
	f = fmemopen(c, sizeof c, "w");
	fwrite("ABCDEFG", 1, 7, f);
	fclose(f);
	printf("fmemopen-clobber: last=%02x (correct 00? no: 7+NUL fills 8 exactly, byte7=NUL is correct) dump=",
		(unsigned char)c[7]);
	for (int i = 0; i < 8; i++)
		printf("%02x", (unsigned char)c[i]);
	printf("\n");
}

static void t_fseeko(void)
{
	FILE *f = tmpfile();
	errno = 0;
	int r = fseeko(f, (off_t)0x8000000000000000LL, SEEK_CUR);
	printf("fseeko-LLONG_MIN: r=%d errno=%d (correct -1 EOVERFLOW=%d)\n",
		r, errno, EOVERFLOW);
	fclose(f);
}

static void t_mntent(void)
{
	FILE *f = tmpfile();
	/* Long but sane line: must parse, not trip stale-offset UB. */
	for (int i = 0; i < 3000; i++)
		fputs("0123456789abcdef", f);
	fputs(" /mnt/gpfs gpfs rw 0 0\n", f);
	rewind(f);
	errno = 0;
	struct mntent *m = getmntent(f);
	printf("mntent-longline: %s (correct /mnt/gpfs)\n",
		m ? m->mnt_dir : "(null)");
	fclose(f);
}

static void t_misc(void)
{
	printf("wcsrchr-absent: %p (correct nil)\n",
		(void *)wcsrchr(L"hello world", L'z'));
	printf("wcsrchr-found: %ls\n", wcsrchr(L"hello world", L'o'));

	void *p = 0;
	errno = 0;
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
	int v = CPU_ISSET(3, &s);
	printf("cpu_isset: %d (correct 0)\n", v);
}

static void t_wordexp(void)
{
	wordexp_t w;
	int r = wordexp("$*", &w, 0);
	printf("wordexp-star: r=%d n=%zu (correct n=0)\n", r, r ? 0 : w.we_wordc);
	if (!r)
		wordfree(&w);
	r = wordexp(")", &w, 0);
	printf("wordexp-bad: r=%d (correct nonzero, stderr intact below)\n", r);
	if (!r)
		wordfree(&w);
	fprintf(stderr, "wordexp-stderr: intact\n");
}

static void t_iconv(void)
{
	iconv_t cd = iconv_open("UTF-8", "GB18030");
	char in[] = "T\xa8\xa4";
	char out[16] = { 0 };
	char *ip = in, *op = out;
	size_t il = sizeof in - 1, ol = sizeof out;
	size_t r = iconv(cd, &ip, &il, &op, &ol);
	printf("iconv-gb18030: r=%zu out=%s (correct T\\xc3\\xa9)\n", r, out);
	iconv_close(cd);

	/* Timing: 200k 4-byte sequences (pathological-slow pre-fix). */
	static char big[800000];
	for (int i = 0; i < 200000; i++) {
		big[4 * i] = '\x82';
		big[4 * i + 1] = '\x35';
		big[4 * i + 2] = '\x8a';
		big[4 * i + 3] = '\x38';
	}
	static char ob[1200000];
	cd = iconv_open("UTF-8", "GB18030");
	ip = big;
	op = ob;
	il = sizeof big;
	ol = sizeof ob;
	clock_t c0 = clock();
	r = iconv(cd, &ip, &il, &op, &ol);
	clock_t c1 = clock();
	printf("iconv-gb18030-bulk: r=%zu left=%zu ms=%ld\n", r, il,
		(long)((c1 - c0) * 1000 / CLOCKS_PER_SEC));
	iconv_close(cd);
}

int main(void)
{
	t_fmemopen();
	t_fseeko();
	t_mntent();
	t_misc();
	t_wordexp();
	t_iconv();
	FILE *f = popen("echo hi", "r");
	char l[16] = { 0 };
	if (f) {
		fgets(l, sizeof l, f);
		pclose(f);
	}
	printf("popen-smoke: %s", l);
	return 0;
}

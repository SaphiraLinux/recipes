/* Saphira allocator edge + huge-overalignment regression
 * (Sinew Item 6).
 *
 * Pins the Item-4 mallocng audit verdicts plus the 2^34
 * aligned_alloc SIGSEGV (fixed by the Sinew tail-shrink +
 * get_meta 64-bit-offset workstream): the huge cases run in
 * forked children so a regression reports FAIL, never a suite
 * ERROR/abort, and repeat across fresh layouts (the defect was
 * layout-dependent).
 *
 * usable==64 after the shrink is musl-exact (dedicated slot,
 * exact books); glibc reports its own value. Saphira lane suite,
 * same convention as the vec-67/68 pins.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <malloc.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <unistd.h>
#include "test.h"

static int failures;

/* Hide probe values from the compiler: GCC folds known-invalid
 * aligned_alloc alignments (and their errno effects) at compile
 * time, which would turn these runtime probes into no-ops. The
 * volatile reload keeps every probe a genuine call. */
static size_t hide(size_t x)
{
	volatile size_t v = x;
	return v;
}

#define CHECK(cond, tag) do { \
	if (!(cond)) { \
		t_error("alloc " tag " failed\n"); \
		failures++; \
	} \
} while (0)

/* run fn in a child; FAIL unless it exits 0 (signal == genuine RED) */
static void in_child(void (*fn)(void), const char *tag)
{
	pid_t p = fork();
	if (p < 0) {
		t_error("alloc %s: fork: %s\n", tag, strerror(errno));
		failures++;
		return;
	}
	if (p == 0) {
		fn();
		_exit(failures ? 1 : 0);
	}
	int st = 0;
	while (waitpid(p, &st, 0) < 0 && errno == EINTR)
		;
	if (!WIFEXITED(st) || WEXITSTATUS(st) != 0) {
		t_error("alloc %s: child %s (status %#x)\n", tag,
			WIFSIGNALED(st) ? "signalled" : "exit!=0",
			(unsigned)st);
		failures++;
	}
}

static void overflow_cases(void)
{
	void *p;
	int e;
	errno = 0; p = malloc(hide((size_t)-1)); e = errno;
	CHECK(!p && e == ENOMEM, "malloc-overflow");
	errno = 0; p = calloc(hide((size_t)-1), 2); e = errno;
	CHECK(!p && e == ENOMEM, "calloc-overflow-a");
	errno = 0; p = calloc(2, hide((size_t)-1)); e = errno;
	CHECK(!p && e == ENOMEM, "calloc-overflow-b");
	errno = 0; p = calloc(hide((size_t)-1), hide((size_t)-1));
	e = errno;
	CHECK(!p && e == ENOMEM, "calloc-overflow-c");
	errno = 0; p = calloc(65536, hide((size_t)1 << 48)); e = errno;
	CHECK(!p && e == ENOMEM, "calloc-overflow-d");
	errno = 0; p = reallocarray(0, hide((size_t)-1), 2); e = errno;
	CHECK(!p && e == ENOMEM, "reallocarray-overflow");
}

static void align_table(void)
{
	/* invalid alignments fail EINVAL; valid ones are exact */
	static const size_t bad[] = {3, 5, 6, 12, 24};
	static const size_t good[] = {0, 1, 2, 4, 8, 16, 32};
	size_t i;
	int e;
	for (i = 0; i < sizeof bad / sizeof *bad; i++) {
		void *p;
		errno = 0; p = aligned_alloc(hide(bad[i]), 64); e = errno;
		CHECK(!p && e == EINVAL, "align-einval");
	}
	for (i = 0; i < sizeof good / sizeof *good; i++) {
		void *p;
		size_t a = good[i] ? good[i] : 16;
		errno = 0; p = aligned_alloc(hide(good[i]), 64); e = errno;
		CHECK(p && (uintptr_t)p % a == 0 && e == 0,
		      "align-ok");
		free(p);
	}
	/* non-multiple size still succeeds (musl upgrades) */
	{
		void *p;
		errno = 0; p = aligned_alloc(16, 20);
		CHECK(p && (uintptr_t)p % 16 == 0, "align-nonmult");
		free(p);
	}
}

static void pmemalign_table(void)
{
	/* Item-4 evidence: 3/4/6/12 rejected (4 is not a multiple of
	 * sizeof(void*)), 8/16/32 exact. Volatile probe values defeat
	 * GCC constant-folding (same hazard as aligned_alloc). */
	static const size_t bad[] = {3, 4, 6, 12};
	static const size_t good[] = {8, 16, 32};
	size_t i;
	int r, e;
	for (i = 0; i < sizeof bad / sizeof *bad; i++) {
		void *mp = (void *)0x1;
		errno = 0; r = posix_memalign(&mp, hide(bad[i]), 64);
		e = errno;
		CHECK(r == EINVAL, "pm-bad");
	}
	for (i = 0; i < sizeof good / sizeof *good; i++) {
		void *mp = NULL;
		errno = 0; r = posix_memalign(&mp, hide(good[i]), 64);
		e = errno;
		CHECK(r == 0 && mp && (uintptr_t)mp % good[i] == 0 &&
		      e == 0, "pm-ok");
		free(mp);
	}
	{
		void *mp = NULL;
		errno = 0; r = posix_memalign(&mp, 16, 0); e = errno;
		CHECK(r == 0 && e == 0, "pm-size0");
		free(mp);
	}
	{
		void *mp = NULL;
		errno = 0; r = posix_memalign(&mp, 16, hide((size_t)-1));
		e = errno;
		CHECK(r == ENOMEM, "pm-sizemax");
		free(mp);
	}
	{
		void *q;
		errno = 0; q = memalign(16, 20); e = errno;
		CHECK(q && (uintptr_t)q % 16 == 0 && e == 0,
		      "memalign-nonmult");
		free(q);
	}
	{
		void *v;
		long ps = sysconf(_SC_PAGESIZE);
		if (ps <= 0) {
			t_error("alloc valloc: no page size\n");
			failures++;
			return;
		}
		errno = 0; v = valloc(64); e = errno;
		CHECK(v && (uintptr_t)v % (size_t)ps == 0 && e == 0,
		      "valloc-page");
		free(v);
	}
}

static void realloc_zero(void)
{
	/* musl OB-conformant option 2: frees old, returns fresh */
	void *p = malloc(64), *q;
	int e;
	if (!p) {
		t_error("alloc realloc-zero setup\n");
		failures++;
		return;
	}
	memset(p, 0x5A, 64);
	errno = 0; q = realloc(p, 0); e = errno;
	CHECK(q && q != p && e == 0, "realloc-zero");
	free(q);
}

static void fail_atomic_child(void)
{
	struct rlimit rl;
	void *p, *q, *s;
	size_t u;
	int e;
	/* bound this child well below the 512M probe (Item-4: 256M) */
	rl.rlim_cur = rl.rlim_max = (rlim_t)256 << 20;
	if (setrlimit(RLIMIT_AS, &rl)) {
		t_error("alloc atomic: setrlimit: %s\n",
			strerror(errno));
		failures++;
		return;
	}
	p = malloc(64);
	if (!p) {
		t_error("alloc atomic: setup malloc\n");
		failures++;
		return;
	}
	memset(p, 0x5A, 64);
	u = malloc_usable_size(p);
	errno = 0; q = realloc(p, hide((size_t)512 << 20)); e = errno;
	CHECK(!q && e == ENOMEM, "realloc-oom");
	CHECK(malloc_usable_size(p) == u, "atomic-intact");
	{
		int i, ok = 1;
		for (i = 0; i < 64; i++)
			if (((unsigned char *)p)[i] != 0x5A)
				ok = 0;
		CHECK(ok, "atomic-content");
	}
	free(p);
	errno = 0; s = malloc(64);
	CHECK(s, "small-after-fail");
	free(s);
}

static void huge_child(void)
{
	/* 2^35 is refused by design (framing limit); 2^33 and
	 * 2^34 must succeed exactly (the 2^34 SIGSEGV is the
	 * fixed defect: layout-dependent, hence repeated). */
	static const size_t aligns[] = {
		(size_t)1 << 33, (size_t)1 << 34,
		(size_t)1 << 34, (size_t)1 << 33,
	};
	size_t i;
	int e;
	for (i = 0; i < sizeof aligns / sizeof *aligns; i++) {
		unsigned char *p;
		size_t u, al = hide(aligns[i]);
		int k, ok;
		errno = 0;
		p = aligned_alloc(al, 64); e = errno;
		if (!p || (uintptr_t)p % al || e) {
			t_error("alloc huge 2^%d: null=%d errno=%d\n",
				(int)(al == ((size_t)1 << 34) ? 34 : 33),
				!p, e);
			failures++;
			continue;
		}
		u = malloc_usable_size(p);
		if (u != 64) {
			t_error("alloc huge: usable=%zu want 64\n", u);
			failures++;
		}
		memset(p, 0xA5, 64);
		ok = 1;
		for (k = 0; k < 64; k++)
			if (p[k] != 0xA5)
				ok = 0;
		if (!ok) {
			t_error("alloc huge: content\n");
			failures++;
		}
		p = realloc(p, 4096);
		if (!p) {
			t_error("alloc huge: regrow\n");
			failures++;
			continue;
		}
		ok = 1;
		for (k = 0; k < 64; k++)
			if (p[k] != 0xA5)
				ok = 0;
		if (!ok) {
			t_error("alloc huge: regrow content\n");
			failures++;
		}
		free(p);
	}
	{
		void *p;
		int e;
		errno = 0; p = aligned_alloc(hide((size_t)1 << 35), 64);
		e = errno;
		if (p || e != ENOMEM) {
			t_error("alloc huge35: want NULL/ENOMEM\n");
			failures++;
			free(p);
		}
	}
}

int main(void)
{
	if (sizeof(void *) < 8) {
		t_error("alloc: 64-bit only\n");
		return 1;
	}
	overflow_cases();
	align_table();
	pmemalign_table();
	realloc_zero();
	in_child(fail_atomic_child, "fail-atomic");
	in_child(huge_child, "huge-2p34");
	if (failures)
		return 1;
	return t_status;
}

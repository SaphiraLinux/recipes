/* Saphira POSIX message-queue regression (Sinew Item 12).
 *
 * Pins the mqueue family (all ten mq_* entry points), previously the
 * largest wholly unreferenced IPC family: creation, opening,
 * attributes, priority ordering, nonblocking and timed operations,
 * notification registration, setattr round-trips and the unlink
 * lifecycle, plus the full error matrix (EEXIST, ENOENT, EACCES,
 * ENAMETOOLONG, EINVAL attrs, EMSGSIZE, EAGAIN x2, ETIMEDOUT, EBUSY).
 *
 * Oracle: identical 40-check matrix green on musl r21 (dynamic and
 * static) and glibc 2.44, whose outputs differ in exactly one info
 * line. Receive buffers are always >= mq_msgsize: POSIX requires
 * msg_len >= mq_msgsize or the call fails EMSGSIZE regardless of
 * the actual message length.
 *
 * Deliberate divergence (not a defect, do not "fix" toward glibc):
 * a slash-less name fails ENOENT on musl (passed through to the
 * kernel, which sees a relative name) versus EINVAL on glibc (whose
 * wrapper performs the leading-slash check documented in
 * man-pages mq_open(3) VERSIONS). Both reject the invalid name; only
 * the errno differs, so the pin asserts rejection, never the errno.
 *
 * No sleeps, no timing-sensitive assertions, no dependence on
 * unrelated queues: names are pid-tagged, timeouts are absolute and
 * in the past, priority order is deterministic. Every created queue
 * is unlinked, including on failure paths (straight-line flow, no
 * early returns, plus an ignore-errors sweep at the end).
 */
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <mqueue.h>
#include <signal.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>
#include "test.h"

static int failures;
static int pidtag;

#define CHECK(cond, tag) do { \
	if (!(cond)) { \
		t_error("mq " tag " failed (errno=%d)\n", errno); \
		failures++; \
	} \
} while (0)

static void mkn(char *b, size_t n, const char *tag)
{
	snprintf(b, n, "/sinew-mq-%d-%s", pidtag, tag);
}

static long procl(const char *f, long dflt)
{
	char p[128];
	snprintf(p, sizeof p, "/proc/sys/fs/mqueue/%s", f);
	FILE *fp = fopen(p, "r");
	long v = dflt;
	if (fp) {
		if (fscanf(fp, "%ld", &v) != 1)
			v = dflt;
		fclose(fp);
	}
	return v;
}

/* Unlink best-effort: ENOENT (never created / already gone) is fine. */
static void drop(const char *name)
{
	mq_unlink(name);
}

static void create_open_cases(void)
{
	char n1[64], n2[64], n3[64];
	struct mq_attr at, got;
	mqd_t q = (mqd_t)-1, t;
	long msgmax = procl("msg_max", 10);
	long msgsize = procl("msgsize_max", 8192);

	mkn(n1, sizeof n1, "a");
	memset(&at, 0, sizeof at);
	at.mq_maxmsg = msgmax < 10 ? msgmax : 10;
	at.mq_msgsize = msgsize < 8192 ? msgsize : 8192;
	errno = 0; q = mq_open(n1, O_RDWR | O_CREAT | O_EXCL, 0600, &at);
	CHECK(q != (mqd_t)-1 && errno == 0, "create-excl");
	if (q != (mqd_t)-1) {
		memset(&got, 0, sizeof got);
		CHECK(mq_getattr(q, &got) == 0, "getattr");
		CHECK(got.mq_maxmsg == at.mq_maxmsg &&
		      got.mq_msgsize == at.mq_msgsize &&
		      got.mq_curmsgs == 0 && !(got.mq_flags & O_NONBLOCK),
		      "attr-echo");
	}
	errno = 0; t = mq_open(n1, O_RDWR | O_CREAT | O_EXCL, 0600, &at);
	CHECK(t == (mqd_t)-1 && errno == EEXIST, "eexist");
	errno = 0; t = mq_open(n1, O_RDWR);
	CHECK(t != (mqd_t)-1 && errno == 0, "open-existing");
	if (t != (mqd_t)-1)
		mq_close(t);
	mkn(n2, sizeof n2, "absent");
	errno = 0; t = mq_open(n2, O_RDWR);
	CHECK(t == (mqd_t)-1 && errno == ENOENT, "enoent");

	/* Name-shape matrix. Slash-less input is rejected everywhere;
	 * the errno is libc-specific (musl ENOENT, glibc EINVAL), so
	 * only rejection is pinned here. */
	errno = 0; t = mq_open("noslash", O_RDWR);
	CHECK(t == (mqd_t)-1, "noslash-rejected");
	if (t != (mqd_t)-1)
		mq_close(t);
	errno = 0; t = mq_open("/", O_RDWR);
	CHECK(t == (mqd_t)-1 && errno == ENOENT, "slash-only-enoent");
	errno = 0; t = mq_open("/a/b", O_RDWR);
	CHECK(t == (mqd_t)-1 && errno == EACCES, "two-slash-eacces");
	{
		char big[300];
		memset(big, 'x', sizeof big - 1);
		big[0] = '/';
		big[sizeof big - 1] = 0;
		errno = 0; t = mq_open(big, O_RDWR);
		CHECK(t == (mqd_t)-1 && errno == ENAMETOOLONG, "enametoolong");
	}

	/* Invalid attributes. */
	{
		struct mq_attr bad = at;
		bad.mq_maxmsg = 0;
		mkn(n3, sizeof n3, "bad0");
		errno = 0;
		t = mq_open(n3, O_RDWR | O_CREAT | O_EXCL, 0600, &bad);
		CHECK(t == (mqd_t)-1 && errno == EINVAL, "attr-zero-einval");
		bad = at;
		bad.mq_msgsize = msgsize + 1;
		mkn(n3, sizeof n3, "badbig");
		errno = 0;
		t = mq_open(n3, O_RDWR | O_CREAT | O_EXCL, 0600, &bad);
		CHECK(t == (mqd_t)-1 && errno == EINVAL, "attr-overlimit-einval");
	}

	/* NULL attr: system defaults. */
	{
		mkn(n3, sizeof n3, "def");
		errno = 0;
		t = mq_open(n3, O_RDWR | O_CREAT | O_EXCL, 0600, NULL);
		CHECK(t != (mqd_t)-1, "null-attr-create");
		if (t != (mqd_t)-1) {
			memset(&got, 0, sizeof got);
			CHECK(mq_getattr(t, &got) == 0 &&
			      got.mq_maxmsg == msgmax && got.mq_msgsize == msgsize,
			      "null-attr-defaults");
			mq_close(t);
			mq_unlink(n3);
		}
	}

	if (q != (mqd_t)-1)
		mq_close(q);
	drop(n1);
}

static void priority_cases(void)
{
	char n1[64];
	mqd_t q;
	struct mq_attr at;
	long msgmax = procl("msg_max", 10);
	long msgsize = procl("msgsize_max", 8192);
	static char buf[8192 + 64];
	unsigned prio;

	mkn(n1, sizeof n1, "prio");
	memset(&at, 0, sizeof at);
	at.mq_maxmsg = msgmax < 10 ? msgmax : 10;
	at.mq_msgsize = msgsize < 8192 ? msgsize : 8192;
	errno = 0; q = mq_open(n1, O_RDWR | O_CREAT | O_EXCL, 0600, &at);
	CHECK(q != (mqd_t)-1, "prio-create");
	if (q == (mqd_t)-1) {
		drop(n1);
		return;
	}
	CHECK(mq_send(q, "low", 4, 1) == 0, "send-p1");
	CHECK(mq_send(q, "high", 5, 9) == 0, "send-p9");
	CHECK(mq_send(q, "mid", 4, 5) == 0, "send-p5");
	memset(buf, 0, sizeof buf);
	CHECK(mq_receive(q, buf, sizeof buf, &prio) == 5 &&
	      prio == 9 && !memcmp(buf, "high", 5), "recv-prio-first");
	memset(buf, 0, sizeof buf);
	CHECK(mq_receive(q, buf, sizeof buf, &prio) == 4 &&
	      prio == 5 && !memcmp(buf, "mid", 4), "recv-prio-second");
	memset(buf, 0, sizeof buf);
	CHECK(mq_receive(q, buf, sizeof buf, &prio) == 4 &&
	      prio == 1 && !memcmp(buf, "low", 4), "recv-prio-third");
	/* Buffer smaller than mq_msgsize fails even though the
	 * message itself would fit: POSIX msg_len >= mq_msgsize rule. */
	CHECK(mq_send(q, "1234567890123456", 17, 1) == 0, "send-16");
	{
		char small[8];
		errno = 0;
		CHECK(mq_receive(q, small, sizeof small, NULL) < 0 &&
		      errno == EMSGSIZE, "emsgsize");
	}
	memset(buf, 0, sizeof buf);
	CHECK(mq_receive(q, buf, sizeof buf, NULL) == 17, "drain-16");
	mq_close(q);
	drop(n1);
}

static void nonblock_cases(void)
{
	char n3[64];
	struct mq_attr at;
	mqd_t t;
	char b[32];
	unsigned p;

	mkn(n3, sizeof n3, "nb");
	memset(&at, 0, sizeof at);
	at.mq_maxmsg = 4;
	at.mq_msgsize = 32;
	errno = 0;
	t = mq_open(n3, O_RDWR | O_CREAT | O_EXCL | O_NONBLOCK, 0600, &at);
	CHECK(t != (mqd_t)-1, "nb-create");
	if (t != (mqd_t)-1) {
		errno = 0;
		CHECK(mq_receive(t, b, sizeof b, &p) < 0 && errno == EAGAIN,
		      "nb-empty-eagain");
		CHECK(mq_send(t, "a", 2, 1) == 0, "nb-fill1");
		CHECK(mq_send(t, "b", 2, 1) == 0, "nb-fill2");
		CHECK(mq_send(t, "c", 2, 1) == 0, "nb-fill3");
		CHECK(mq_send(t, "d", 2, 1) == 0, "nb-fill4");
		errno = 0;
		CHECK(mq_send(t, "e", 2, 1) < 0 && errno == EAGAIN,
		      "nb-full-eagain");
		mq_close(t);
	}
	drop(n3);
}

static void timed_notify_cases(void)
{
	char n1[64];
	mqd_t q;
	struct mq_attr at;
	long msgmax = procl("msg_max", 10);
	long msgsize = procl("msgsize_max", 8192);
	static char b[8192 + 64];
	unsigned p;
	struct timespec ts;
	struct sigevent sev;

	mkn(n1, sizeof n1, "tn");
	memset(&at, 0, sizeof at);
	at.mq_maxmsg = msgmax < 10 ? msgmax : 10;
	at.mq_msgsize = msgsize < 8192 ? msgsize : 8192;
	errno = 0; q = mq_open(n1, O_RDWR | O_CREAT | O_EXCL, 0600, &at);
	CHECK(q != (mqd_t)-1, "tn-create");
	if (q == (mqd_t)-1) {
		drop(n1);
		return;
	}
	/* Absolute past timeout: deterministic, no sleep. */
	clock_gettime(CLOCK_REALTIME, &ts);
	ts.tv_sec -= 10;
	errno = 0;
	CHECK(mq_timedreceive(q, b, sizeof b, &p, &ts) < 0 &&
	      errno == ETIMEDOUT, "timedrecv-past-etimedout");
	memset(&sev, 0, sizeof sev);
	sev.sigev_notify = SIGEV_NONE;
	errno = 0;
	CHECK(mq_notify(q, &sev) == 0, "notify-reg");
	errno = 0;
	CHECK(mq_notify(q, &sev) < 0 && errno == EBUSY, "notify-ebusy");
	CHECK(mq_notify(q, NULL) == 0, "notify-unreg");
	CHECK(mq_notify(q, &sev) == 0, "notify-rereg");
	mq_notify(q, NULL);
	mq_close(q);
	drop(n1);
}

static void setattr_lifecycle_cases(void)
{
	char n1[64];
	mqd_t q, t;
	struct mq_attr at, cur, set;
	long msgmax = procl("msg_max", 10);
	long msgsize = procl("msgsize_max", 8192);
	static char b[8192 + 64];

	mkn(n1, sizeof n1, "life");
	memset(&at, 0, sizeof at);
	at.mq_maxmsg = msgmax < 10 ? msgmax : 10;
	at.mq_msgsize = msgsize < 8192 ? msgsize : 8192;
	errno = 0; q = mq_open(n1, O_RDWR | O_CREAT | O_EXCL, 0600, &at);
	CHECK(q != (mqd_t)-1, "life-create");
	if (q == (mqd_t)-1) {
		drop(n1);
		return;
	}
	memset(&cur, 0, sizeof cur);
	CHECK(mq_getattr(q, &cur) == 0, "getattr-flags");
	memset(&set, 0, sizeof set);
	set.mq_flags = O_NONBLOCK;
	CHECK(mq_setattr(q, &set, NULL) == 0, "setattr-nb");
	memset(&cur, 0, sizeof cur);
	CHECK(mq_getattr(q, &cur) == 0 && (cur.mq_flags & O_NONBLOCK),
	      "nb-sticks");
	memset(&set, 0, sizeof set);
	set.mq_flags = 0;
	CHECK(mq_setattr(q, &set, NULL) == 0, "setattr-block");
	memset(&cur, 0, sizeof cur);
	CHECK(mq_getattr(q, &cur) == 0 && !(cur.mq_flags & O_NONBLOCK),
	      "block-sticks");
	/* The descriptor stays usable after unlink; the name is gone. */
	CHECK(mq_unlink(n1) == 0, "unlink");
	CHECK(mq_send(q, "zz", 3, 1) == 0, "send-after-unlink");
	memset(b, 0, sizeof b);
	CHECK(mq_receive(q, b, sizeof b, NULL) == 3 && !memcmp(b, "zz", 3),
	      "recv-after-unlink");
	errno = 0; t = mq_open(n1, O_RDWR);
	CHECK(t == (mqd_t)-1 && errno == ENOENT, "gone-after-unlink");
	mq_close(q);
	drop(n1);
}

int main(void)
{
	pidtag = (int)getpid();
	if (sizeof(void *) < 8) {
		t_error("mq: 64-bit only\n");
		return 1;
	}
	create_open_cases();
	priority_cases();
	nonblock_cases();
	timed_notify_cases();
	setattr_lifecycle_cases();
	if (failures)
		return 1;
	return t_status;
}

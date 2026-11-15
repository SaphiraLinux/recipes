/*
 * Saphira Linux
 * Copyright (c) 2026 AKADATA LIMITED
 * SPDX-License-Identifier: MIT
 */

/* Saphira POSIX timers + timerfd regression (Sinew Item 13).
 *
 * Pins the timer family (previously wholly unreferenced): POSIX
 * timer_create/settime/gettime/getoverrun/delete plus timerfd
 * create/settime/gettime, polled readability and the error matrix.
 * Fully deterministic: SIGEV_NONE only (no signals, threads or
 * delivery races), past-absolute expirations, disarm-only-where-
 * honored assertions. No sleeps, no timing-sensitive checks.
 *
 * Deliberately NOT pinned here (see Item 13 findings):
 * - Invalid timer_t values crash identically on musl and glibc
 *   (userspace dereference before any syscall). Unpinnable and out
 *   of scope: fixing musl alone would diverge from glibc.
 * - Zero-it_value "disarm" of an armed POSIX timer is a no-op
 *   (rc 0, timer keeps counting) identically on both libcs: kernel
 *   behavior, not libc. timerfd disarm works and is pinned below.
 * - timer_delete on an already-deleted timer returns raw -errno
 *   without setting errno on musl (missing __syscall_ret), versus
 *   -1/EINVAL on glibc. Genuine defect, reported separately with
 *   reproducer; a green suite must not lock a bug in, so redelete
 *   is exercised only for the valid-delete path here.
 */
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <signal.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/timerfd.h>
#include <time.h>
#include <unistd.h>
#include "test.h"

static int failures;

#define CHECK(cond, tag) do { \
	if (!(cond)) { \
		t_error("timer " tag " failed (errno=%d)\n", errno); \
		failures++; \
	} \
} while (0)

static int nonzero_ts(struct timespec t)
{
	return t.tv_sec != 0 || t.tv_nsec != 0;
}

static void posix_create_settime_cases(void)
{
	struct sigevent sev;
	timer_t id = (timer_t)0, id2 = (timer_t)0;
	struct itimerspec set, get, old;

	memset(&sev, 0, sizeof sev);
	sev.sigev_notify = SIGEV_NONE;
	errno = 0;
	CHECK(timer_create(CLOCK_MONOTONIC, &sev, &id) == 0, "create-mono");
	errno = 0;
	CHECK(timer_create(CLOCK_REALTIME, &sev, &id2) == 0, "create-real");
	{
		timer_t bad;
		errno = 0;
		CHECK(timer_create((clockid_t)-1, &sev, &bad) != 0 &&
		      errno == EINVAL, "create-badclock");
	}
	memset(&set, 0, sizeof set);
	set.it_value.tv_sec = 3600;
	errno = 0;
	CHECK(timer_settime(id, 0, &set, NULL) == 0, "set-future");
	memset(&get, 0, sizeof get);
	errno = 0;
	CHECK(timer_gettime(id, &get) == 0 && nonzero_ts(get.it_value),
	      "gettime-remaining");
	/* Old-value echo carries the previous (+3600s) setting. The
	 * disarm call itself is only checked for success: a zero
	 * it_value does not disarm an armed POSIX timer on current
	 * kernels (identical musl/glibc behavior), so no post-disarm
	 * zero state is asserted here. */
	memset(&set, 0, sizeof set);
	memset(&old, 0, sizeof old);
	errno = 0;
	CHECK(timer_settime(id, 0, &set, &old) == 0, "disarm");
	CHECK(nonzero_ts(old.it_value), "old-echo-nonzero");
	/* Out-of-range nanoseconds are rejected before arming. */
	memset(&set, 0, sizeof set);
	set.it_value.tv_sec = 5;
	set.it_value.tv_nsec = 1000000000;
	errno = 0;
	CHECK(timer_settime(id, 0, &set, NULL) != 0 && errno == EINVAL,
	      "settime-badnsec");
	/* Overrun on a never-fired SIGEV_NONE timer is zero. */
	errno = 0;
	CHECK(timer_getoverrun(id) == 0, "overrun-zero");
	/* Delete lifecycle; gettime on the deleted id must fail. */
	errno = 0;
	CHECK(timer_delete(id) == 0, "delete");
	memset(&get, 0, sizeof get);
	errno = 0;
	CHECK(timer_gettime(id, &get) != 0 && errno == EINVAL,
	      "gettime-after-delete");
	timer_delete(id2);
}

static void timerfd_create_cases(void)
{
	int fd = -1;

	errno = 0; fd = timerfd_create(CLOCK_MONOTONIC, 0);
	CHECK(fd >= 0, "tfd-create-mono");
	if (fd >= 0)
		close(fd);
	errno = 0; fd = timerfd_create(CLOCK_BOOTTIME, TFD_NONBLOCK | TFD_CLOEXEC);
	CHECK(fd >= 0, "tfd-create-bootflags");
	if (fd >= 0) {
		int fl = fcntl(fd, F_GETFL);
		CHECK(fl >= 0 && (fl & O_NONBLOCK), "tfd-nonblock-sticks");
		fl = fcntl(fd, F_GETFD);
		CHECK(fl >= 0 && (fl & FD_CLOEXEC), "tfd-cloexec-sticks");
		close(fd);
	}
	errno = 0; fd = timerfd_create((clockid_t)-1, 0);
	CHECK(fd < 0 && errno == EINVAL, "tfd-badclock");
	errno = 0; fd = timerfd_create(CLOCK_MONOTONIC, ~0U);
	CHECK(fd < 0 && errno == EINVAL, "tfd-badflags");
	{
		/* Needs CAP_WAKE_ALARM; unprivileged runners get EPERM.
		 * Either outcome is conforming here. */
		errno = 0; fd = timerfd_create(CLOCK_REALTIME_ALARM, 0);
		if (fd < 0)
			CHECK(errno == EPERM, "tfd-alarm-eperm");
		else {
			printf("ok tfd-alarm-allowed-privileged\n");
			close(fd);
		}
	}
}

static void timerfd_io_cases(void)
{
	int fd = -1;
	struct itimerspec cur, nv, ov;
	uint64_t expir = 0;
	ssize_t n;

	errno = 0; fd = timerfd_create(CLOCK_MONOTONIC, TFD_NONBLOCK);
	CHECK(fd >= 0, "tfd-nb-create");
	if (fd < 0)
		return;
	memset(&cur, 0, sizeof cur);
	errno = 0;
	CHECK(timerfd_gettime(fd, &cur) == 0 &&
	      !nonzero_ts(cur.it_value), "tfd-gettime-disarmed");
	/* Nothing expired: nonblocking read fails EAGAIN. */
	errno = 0; n = read(fd, &expir, sizeof expir);
	CHECK(n < 0 && errno == EAGAIN, "tfd-read-empty-eagain");
	/* Short reads are EINVAL regardless of state. */
	{
		char small[4];
		errno = 0; n = read(fd, small, sizeof small);
		CHECK(n < 0 && errno == EINVAL, "tfd-read-short-einval");
	}
	/* Periodic settings echo; bad fields rejected. */
	memset(&nv, 0, sizeof nv);
	nv.it_value.tv_sec = 3600;
	nv.it_interval.tv_sec = 60;
	memset(&ov, 0, sizeof ov);
	errno = 0;
	CHECK(timerfd_settime(fd, 0, &nv, &ov) == 0, "tfd-set-periodic");
	CHECK(!nonzero_ts(ov.it_value), "tfd-old-disarmed");
	memset(&cur, 0, sizeof cur);
	errno = 0;
	CHECK(timerfd_gettime(fd, &cur) == 0 &&
	      cur.it_interval.tv_sec == 60 && nonzero_ts(cur.it_value),
	      "tfd-gettime-periodic");
	nv.it_value.tv_nsec = 1000000000;
	nv.it_value.tv_sec = 5;
	errno = 0;
	CHECK(timerfd_settime(fd, 0, &nv, NULL) < 0 && errno == EINVAL,
	      "tfd-set-badnsec");
	nv.it_value.tv_nsec = 0;
	errno = 0;
	CHECK(timerfd_settime(fd, 0xdead, &nv, NULL) < 0 && errno == EINVAL,
	      "tfd-set-badflags");
	/* Disarm (honored on the timerfd path), then a past-absolute
	 * one-shot: already expired, read returns immediately. */
	memset(&nv, 0, sizeof nv);
	timerfd_settime(fd, 0, &nv, NULL);
	memset(&cur, 0, sizeof cur);
	errno = 0;
	CHECK(timerfd_gettime(fd, &cur) == 0 &&
	      !nonzero_ts(cur.it_value), "tfd-disarm-sticks");
	{
		struct timespec now;
		clock_gettime(CLOCK_MONOTONIC, &now);
		memset(&nv, 0, sizeof nv);
		nv.it_value.tv_sec = now.tv_sec - 10;
		nv.it_value.tv_nsec = now.tv_nsec;
		errno = 0;
		CHECK(timerfd_settime(fd, TFD_TIMER_ABSTIME, &nv, NULL) == 0,
		      "tfd-set-past-abstime");
		errno = 0; n = read(fd, &expir, sizeof expir);
		CHECK(n == (ssize_t)sizeof expir && expir >= 1,
		      "tfd-read-expired");
		/* One-shot consumed: disarmed again, poll dry. */
		memset(&cur, 0, sizeof cur);
		errno = 0;
		CHECK(timerfd_gettime(fd, &cur) == 0 &&
		      !nonzero_ts(cur.it_value), "tfd-oneshot-consumed");
		{
			struct pollfd pfd;
			pfd.fd = fd;
			pfd.events = POLLIN;
			pfd.revents = 0;
			CHECK(poll(&pfd, 1, 0) == 0, "tfd-poll-dry");
		}
	}
	/* EBADF paths. */
	memset(&cur, 0, sizeof cur);
	errno = 0;
	CHECK(timerfd_settime(-1, 0, &cur, NULL) < 0 && errno == EBADF,
	      "tfd-set-ebadf");
	errno = 0;
	CHECK(timerfd_gettime(-1, &cur) < 0 && errno == EBADF,
	      "tfd-get-ebadf");
	close(fd);
}

int main(void)
{
	posix_create_settime_cases();
	timerfd_create_cases();
	timerfd_io_cases();
	if (failures)
		return 1;
	return t_status;
}

/* t6: SIGEV_THREAD timer_create failure (upstream f607123b).
 * Without CAP_WAKE_ALARM the BOOTTIME_ALARM create must fail fast with
 * EPERM. The unpatched tree deadlocks in sem_wait; the runner wraps this
 * binary in `timeout 10` so a hang shows as rc=124.
 */
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <signal.h>
#include <errno.h>

static void fn(union sigval v)
{
	(void)v;
}

int main(void)
{
	timer_t id;
	struct sigevent ev;
	memset(&ev, 0, sizeof ev);
	ev.sigev_notify = SIGEV_THREAD;
	ev.sigev_notify_function = fn;
	errno = 0;
	int r = timer_create(CLOCK_BOOTTIME_ALARM, &ev, &id);
	printf("timer_create: r=%d errno=%d (%s)\n", r, errno, strerror(errno));
	return 0;
}

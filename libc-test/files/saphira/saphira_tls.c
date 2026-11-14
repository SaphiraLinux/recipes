/* Saphira TLS: _Thread_local storage is per-thread.
 * Each thread must see its own copy; the main thread value stays put. */
#include <pthread.h>
#include <stdio.h>
#include "test.h"


static _Thread_local int mine;
static int failures;

static void *worker(void *arg)
{
	long id = (long)arg;
	mine = (int)(1000 + id);
	/* spin briefly so threads overlap */
	for (volatile long i = 0; i < 1000000; i++)
		;
	if (mine != 1000 + id) {
		t_error("thread %ld sees %d, want %ld\n", id, mine, 1000 + id);
		__atomic_add_fetch(&failures, 1, __ATOMIC_RELAXED);
	}
	return 0;
}

int main(void)
{
	pthread_t t[4];
	long i;
	mine = -1;
	for (i = 0; i < 4; i++)
		if (pthread_create(&t[i], 0, worker, (void *)i)) {
			t_error("pthread_create %ld failed\n", i);
			return 1;
		}
	for (i = 0; i < 4; i++)
		pthread_join(t[i], 0);
	if (mine != -1) {
		t_error("main thread value clobbered: %d\n", mine);
		return 1;
	}
	if (failures)
		return 1;
	return t_status;
}

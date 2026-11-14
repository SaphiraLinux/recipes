/* Saphira threads: mutex-protected counter + condvar handshake.
 * 4 threads x N increments must total exactly; a signalled waiter
 * must wake exactly once. */
#include <pthread.h>
#include <stdio.h>
#include "test.h"


#define NTHREAD 4
#define NINC 50000

static pthread_mutex_t mtx = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t cond = PTHREAD_COND_INITIALIZER;
static long total;
static int ready, woke;

static void *counter(void *arg)
{
	long i;
	(void)arg;
	for (i = 0; i < NINC; i++) {
		pthread_mutex_lock(&mtx);
		total++;
		pthread_mutex_unlock(&mtx);
	}
	return 0;
}

static void *waiter(void *arg)
{
	(void)arg;
	pthread_mutex_lock(&mtx);
	while (!ready)
		pthread_cond_wait(&cond, &mtx);
	woke++;
	pthread_mutex_unlock(&mtx);
	return 0;
}

int main(void)
{
	pthread_t t[NTHREAD], w;
	long i;
	for (i = 0; i < NTHREAD; i++)
		if (pthread_create(&t[i], 0, counter, 0)) {
			t_error("pthread_create failed\n");
			return 1;
		}
	if (pthread_create(&w, 0, waiter, 0)) {
		t_error("waiter create failed\n");
		return 1;
	}
	for (i = 0; i < NTHREAD; i++)
		pthread_join(t[i], 0);
	if (total != (long)NTHREAD * NINC) {
		t_error("counter %ld, want %ld\n", total, (long)NTHREAD * NINC);
		return 1;
	}
	pthread_mutex_lock(&mtx);
	ready = 1;
	pthread_cond_signal(&cond);
	pthread_mutex_unlock(&mtx);
	pthread_join(w, 0);
	if (woke != 1) {
		t_error("woke=%d, want 1\n", woke);
		return 1;
	}
	return t_status;
}

/* t16: thread-cancellation around scandir (upstream 187765a3) plus
 * general cancellation smoke. A worker loops scandir() over a
 * populated directory while main cancels+joins it 50 times. Success:
 * every join completes (no hang), fd count is stable (no leak), no
 * crash. Directory is created under cwd by the runner. */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <dirent.h>
#include <pthread.h>
#include <unistd.h>

static void *worker(void *arg)
{
	(void)arg;
	for (;;) {
		struct dirent **nl = 0;
		int n = scandir("t16dir", &nl, 0, alphasort);
		if (n > 0) {
			for (int i = 0; i < n; i++)
				free(nl[i]);
			free(nl);
		}
		pthread_testcancel();
	}
	return 0;
}

static int fdcount(void)
{
	int n = 0;
	DIR *d = opendir("/proc/self/fd");
	if (!d)
		return -1;
	while (readdir(d))
		n++;
	closedir(d);
	return n - 2; /* . and .. */
}

int main(void)
{
	system("rm -rf t16dir && mkdir -p t16dir");
	for (int i = 0; i < 2000; i++) {
		char p[64];
		snprintf(p, sizeof p, "t16dir/f%04d", i);
		FILE *f = fopen(p, "w");
		if (f)
			fclose(f);
	}
	int before = fdcount();
	int cancels = 0;
	for (int i = 0; i < 50; i++) {
		pthread_t td;
		if (pthread_create(&td, 0, worker, 0) != 0) {
			printf("create-fail iter %d\n", i);
			return 1;
		}
		usleep(1000);
		pthread_cancel(td);
		void *res = 0;
		if (pthread_join(td, &res) != 0) {
			printf("join-fail iter %d\n", i);
			return 1;
		}
		if (res == PTHREAD_CANCELED)
			cancels++;
	}
	int after = fdcount();
	printf("cancel-join: 50 iters, canceled=%d fd-before=%d fd-after=%d %s\n",
		cancels, before, after,
		(before == after) ? "stable-OK" : "LEAKED");
	return 0;
}

/* t5: scandir series (upstream 4dad8af7, 0270c6f0, 0c34aa68, 187765a3,
 * 194f3481, b5934c40) + qsort stress (upstream 228da39e, b3291b9a, 5122f9f3).
 */
#define _GNU_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <dirent.h>

static int seen_errno = -1;

static int sel(const struct dirent *d)
{
	seen_errno = errno;
	return d->d_name[0] != '.';
}

static int cmp_int(const void *a, const void *b)
{
	int x = *(const int *)a, y = *(const int *)b;
	return (x > y) - (x < y);
}

int main(void)
{
	system("rm -rf t5dir && mkdir -p t5dir && touch t5dir/b t5dir/a t5dir/c");
	struct dirent **nl = 0;
	errno = 0x5A5A5A;
	int n = scandir("t5dir", &nl, sel, versionsort);
	/* Correct: sel must observe the caller's errno, not an internal 0. */
	printf("scandir: n=%d sel_errno=0x%x (correct 0x5a5a5a)\n", n, seen_errno);
	for (int i = 0; i < n; i++) {
		printf("  entry %s\n", nl[i]->d_name);
		free(nl[i]);
	}
	free(nl);

	int N = 200000;
	int *v = malloc((size_t)N * sizeof *v);
	unsigned s = 12345;
	for (int i = 0; i < N; i++) {
		s = s * 1103515245 + 12345;
		v[i] = (int)(s >> 8);
	}
	qsort(v, (size_t)N, sizeof *v, cmp_int);
	int bad = 0;
	for (int i = 1; i < N; i++)
		if (v[i - 1] > v[i])
			bad++;
	printf("qsort-200k: %s\n", bad ? "MISORDERED" : "sorted-OK");
	free(v);
	return 0;
}

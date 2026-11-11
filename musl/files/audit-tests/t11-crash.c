/* t11: isolate the two baseline crash sites (upstream 15a1155e wcsrchr,
 * upstream bf96b52a mallocng extreme alignment). argv[1] selects. */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include <stdint.h>

int main(int argc, char **argv)
{
	const char *which = argc > 1 ? argv[1] : "all";
	if (!strcmp(which, "wcsrchr") || !strcmp(which, "all")) {
		void *p = wcsrchr(L"hello world", L'z');
		printf("wcsrchr-absent: %p (correct nil)\n", p);
		printf("wcsrchr-found: %ls\n", wcsrchr(L"hello world", L'o'));
	}
	if (!strcmp(which, "memalign") || !strcmp(which, "all")) {
		void *p = 0;
		int r = posix_memalign(&p, 1U << 24, 16);
		printf("memalign-huge: r=%d aligned=%d\n", r,
			p ? (int)(((uintptr_t)p & ((1U << 24) - 1)) == 0) : -1);
		free(p);
	}
	return 0;
}

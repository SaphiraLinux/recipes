/* t13: strerror-family INT_MIN/MAX probes (upstream c5e2f7e7) standalone. */
#define _GNU_SOURCE
#include <stdio.h>
#include <netdb.h>
#include <regex.h>

int main(void)
{
	printf("gai: %s\n", gai_strerror(2147483647));
	fflush(stdout);
	printf("hstr: %s\n", hstrerror(-2147483647 - 1));
	fflush(stdout);
	char eb[128];
	size_t n = regerror(-2147483647 - 1, 0, eb, sizeof eb);
	printf("regerr: n=%zu %s\n", n, eb);
	fflush(stdout);
	return 0;
}

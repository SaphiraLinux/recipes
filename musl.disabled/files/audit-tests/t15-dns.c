/* t15: DNS/resolver behaviour (upstream 6f6bd4a1 OOB, 89793723
 * attempts:0). argv[1] selects: "smoke" (localhost/numeric, no DNS
 * traffic) or "attempts0" (expects resolv.conf with `options attempts:0`;
 * baseline divides by zero -> SIGFPE, patched returns an EAI error).
 * Run attempts0 under timeout; rc 136 (SIGFPE) reproduces the bug. */
#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>
#include <netdb.h>
#include <sys/socket.h>

static void q(const char *host)
{
	struct addrinfo hints, *res = 0;
	memset(&hints, 0, sizeof hints);
	int r = getaddrinfo(host, "80", &hints, &res);
	printf("getaddrinfo(%s) -> %d (%s)\n", host, r, gai_strerror(r));
	if (!r)
		freeaddrinfo(res);
}

int main(int argc, char **argv)
{
	const char *mode = argc > 1 ? argv[1] : "smoke";
	if (!strcmp(mode, "smoke")) {
		q("localhost");
		q("127.0.0.1");
		q("nonexistent.invalid");
		return 0;
	}
	/* attempts0: resolv.conf must carry `options attempts:0`. */
	q("nonexistent.invalid");
	return 0;
}

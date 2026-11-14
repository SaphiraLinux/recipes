/* Saphira DNS: localhost + numeric resolution only (hermetic,
 * no network). getaddrinfo on "localhost" must yield a loopback
 * address; numeric input must not touch the network. */
#include <netdb.h>
#include <stdio.h>
#include <string.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include "test.h"


int main(void)
{
	struct addrinfo hints, *res, *r;
	int found4 = 0, found6 = 0, rc;
	char host[64];

	memset(&hints, 0, sizeof hints);
	hints.ai_family = AF_UNSPEC;
	hints.ai_socktype = SOCK_STREAM;
	rc = getaddrinfo("localhost", "80", &hints, &res);
	if (rc != 0) {
		t_error("localhost: %s\n", gai_strerror(rc));
		return 1;
	}
	for (r = res; r; r = r->ai_next) {
		if (r->ai_family == AF_INET) {
			struct sockaddr_in *a = (struct sockaddr_in *)r->ai_addr;
			if (a->sin_addr.s_addr == htonl(INADDR_LOOPBACK))
				found4 = 1;
		} else if (r->ai_family == AF_INET6) {
			struct sockaddr_in6 *a = (struct sockaddr_in6 *)r->ai_addr;
			static const unsigned char loop[16] = { [15] = 1 };
			if (!memcmp(&a->sin6_addr, loop, 16))
				found6 = 1;
		}
	}
	freeaddrinfo(res);
	if (!found4 && !found6) {
		t_error("localhost gave no loopback\n");
		return 1;
	}

	/* numeric: must succeed without any resolver traffic */
	memset(&hints, 0, sizeof hints);
	hints.ai_family = AF_INET;
	hints.ai_flags = AI_NUMERICHOST;
	rc = getaddrinfo("127.0.0.1", 0, &hints, &res);
	if (rc != 0) {
		t_error("numeric: %s\n", gai_strerror(rc));
		return 1;
	}
	rc = getnameinfo(res->ai_addr, res->ai_addrlen,
			 host, sizeof host, 0, 0, NI_NUMERICHOST);
	freeaddrinfo(res);
	if (rc != 0 || strcmp(host, "127.0.0.1")) {
		t_error("numeric round trip failed: %s\n", host);
		return 1;
	}
	return t_status;
}

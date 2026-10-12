/* saphira-udpdist - udp-sink: generic UDP receiver for the lab. BUSL-1.1, see LICENSE */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <signal.h>
#include <errno.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <netdb.h>

static volatile sig_atomic_t stop_now;

static void onsig(int s) { (void)s; stop_now = 1; }

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "Usage: %s HOST PORT [COUNT] [EXPECT] [ECHO]\n", argv[0]);
        return 2;
    }
    long want = (argc > 3) ? atol(argv[3]) : 0;
    const char *expect = (argc > 4) ? argv[4] : NULL;
    int echo_back = (argc > 5) ? atoi(argv[5]) : 0;

    struct addrinfo hints, *res;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_DGRAM;
    hints.ai_flags = AI_PASSIVE;
    if (getaddrinfo(argv[1], argv[2], &hints, &res) != 0) {
        fprintf(stderr, "%s: cannot resolve %s:%s\n", argv[0], argv[1], argv[2]);
        return 1;
    }
    int fd = -1;
    for (struct addrinfo *r = res; r; r = r->ai_next) {
        fd = socket(r->ai_family, r->ai_socktype, r->ai_protocol);
        if (fd < 0) continue;
        int one = 1;
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
        if (bind(fd, r->ai_addr, r->ai_addrlen) == 0) break;
        close(fd);
        fd = -1;
    }
    freeaddrinfo(res);
    if (fd < 0) {
        fprintf(stderr, "%s: bind %s:%s: %s\n", argv[0], argv[1], argv[2], strerror(errno));
        return 1;
    }

    signal(SIGINT, onsig);
    signal(SIGTERM, onsig);

    char from[INET6_ADDRSTRLEN] = "?";
    uint8_t buf[65536];
    long got = 0, hits = 0;
    while (!stop_now) {
        struct sockaddr_storage ss;
        socklen_t sl = sizeof(ss);
        ssize_t n = recvfrom(fd, buf, sizeof(buf), 0, (struct sockaddr *)&ss, &sl);
        if (n < 0) {
            if (errno == EINTR) continue;
            break;
        }
        got++;
        if (ss.ss_family == AF_INET)
            inet_ntop(AF_INET, &((struct sockaddr_in *)&ss)->sin_addr, from, sizeof(from));
        else
            inet_ntop(AF_INET6, &((struct sockaddr_in6 *)&ss)->sin6_addr, from, sizeof(from));
        if (expect) {
            buf[n < (ssize_t)sizeof(buf) ? n : (ssize_t)sizeof(buf) - 1] = 0;
            if (strstr((char *)buf, expect)) {
                hits++;
                printf("HIT from %s port %u len %zd\n", from,
                       ss.ss_family == AF_INET
                       ? ntohs(((struct sockaddr_in *)&ss)->sin_port)
                       : ntohs(((struct sockaddr_in6 *)&ss)->sin6_port), n);
                fflush(stdout);
            }
        } else {
            printf("datagram from %s len %zd\n", from, n);
            fflush(stdout);
        }
        if (echo_back) {
            /* Reply straight to the sender. Under DSR the reply leaves from the
             * address this socket is bound to, i.e. the VIP, and never passes
             * through the distributor. */
            ssize_t w = sendto(fd, buf, (size_t)n, 0, (struct sockaddr *)&ss, sl);
            if (w < 0) {
                fprintf(stderr, "udp-sink: reply: %s\n", strerror(errno));
                break;
            }
        }
        if (want && got >= want) break;
    }
    printf("received=%ld hits=%ld\n", got, hits);
    close(fd);
    if (want && got < want) return 1;
    if (expect && hits < want) return 1;
    return 0;
}

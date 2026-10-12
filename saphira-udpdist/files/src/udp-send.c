/* saphira-udpdist - udp-send: generic UDP traffic generator. BUSL-1.1, see LICENSE */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <time.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <netdb.h>

static int resolve(const char *s, struct sockaddr_storage *ss, socklen_t *sl,
                   const char *port) {
    memset(ss, 0, sizeof(*ss));
    struct addrinfo hints, *res;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_DGRAM;
    if (getaddrinfo(s, port, &hints, &res) != 0) return -1;
    memcpy(ss, res->ai_addr, res->ai_addrlen);
    *sl = res->ai_addrlen;
    freeaddrinfo(res);
    return 0;
}

int main(int argc, char **argv) {
    long wait_replies = 0;
    if (argc < 3) {
        fprintf(stderr, "Usage: %s HOST PORT [COUNT] [PAYLOAD] [SOURCE_PORT] "
                        "[WAIT_REPLIES]\n", argv[0]);
        return 2;
    }
    long count = (argc > 3) ? atol(argv[3]) : 1;
    const char *payload = (argc > 4) ? argv[4] : "PAYLOADMARK";
    long sport = (argc > 5) ? atol(argv[5]) : 0;
    if (argc > 6) wait_replies = atol(argv[6]);

    struct sockaddr_storage dst, src;
    socklen_t dlen = 0, slen = 0;
    if (resolve(argv[1], &dst, &dlen, argv[2]) != 0) {
        fprintf(stderr, "%s: cannot resolve %s:%s\n", argv[0], argv[1], argv[2]);
        return 1;
    }
    if (sport) {
        char sp[16];
        snprintf(sp, sizeof(sp), "%ld", sport);
        if (resolve("0.0.0.0", &src, &slen, sp) != 0) {
            fprintf(stderr, "%s: cannot bind source port %ld\n", argv[0], sport);
            return 1;
        }
    }

    int fd = socket(dst.ss_family, SOCK_DGRAM, IPPROTO_UDP);
    if (fd < 0) { perror("socket"); return 1; }
    if (sport) {
        if (bind(fd, (struct sockaddr *)&src, slen) != 0) {
            fprintf(stderr, "%s: bind: %s\n", argv[0], strerror(errno));
            return 1;
        }
    }

    size_t plen = strlen(payload);
    uint8_t *pkt = malloc(plen);
    if (!pkt) return 1;
    memcpy(pkt, payload, plen);

    long sent = 0;
    for (long i = 0; i < count; i++) {
        ssize_t n = sendto(fd, pkt, plen, 0, (struct sockaddr *)&dst, dlen);
        if (n < 0) {
            fprintf(stderr, "%s: sendto: %s\n", argv[0], strerror(errno));
            break;
        }
        sent++;
        if (count > 1) usleep(1000);
    }
    printf("sent %ld datagram(s) of %zu bytes to %s:%s from port %ld\n",
           sent, plen, argv[1], argv[2], sport);

    long got = 0;
    if (wait_replies > 0) {
        struct timeval tv;
        tv.tv_sec = 3;
        tv.tv_usec = 0;
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        uint8_t rb[65536];
        char from[INET6_ADDRSTRLEN];
        while (got < wait_replies) {
            struct sockaddr_storage ss;
            socklen_t sl = sizeof(ss);
            ssize_t n = recvfrom(fd, rb, sizeof(rb), 0, (struct sockaddr *)&ss, &sl);
            if (n < 0) break;
            got++;
            if (ss.ss_family == AF_INET) {
                struct sockaddr_in *s4 = (struct sockaddr_in *)&ss;
                inet_ntop(AF_INET, &s4->sin_addr, from, sizeof(from));
                printf("reply %ld from %s:%u len %zd\n", got, from, ntohs(s4->sin_port), n);
            } else {
                struct sockaddr_in6 *s6 = (struct sockaddr_in6 *)&ss;
                inet_ntop(AF_INET6, &s6->sin6_addr, from, sizeof(from));
                printf("reply %ld from [%s]:%u len %zd\n", got, from, ntohs(s6->sin6_port), n);
            }
        }
        printf("received %ld of %ld expected repl%s\n", got, wait_replies,
               wait_replies == 1 ? "y" : "ies");
    }

    close(fd);
    free(pkt);
    if (sent != count) return 1;
    if (wait_replies > 0 && got < wait_replies) return 1;
    return 0;
}

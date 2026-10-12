/* saphira-udpdist - in-process ICMP/ICMPv6 health probing. BUSL-1.1, see LICENSE */
#include "udpdist.h"

#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/ip_icmp.h>
#include <netinet/icmp6.h>
#include <netinet/ip6.h>
#include <sys/select.h>
#include <sys/time.h>

#define ICMP_ECHO_REPLY 0
#define ICMP6_ECHO_REPLY 129

static int icmp4_fd = -1;
static int icmp6_fd = -1;
static uint64_t sent_ms[UD_MAX_BACKENDS];
static int pending[UD_MAX_BACKENDS];

static uint16_t ck16(const uint8_t *p, size_t n, uint32_t acc) {
    while (n > 1) {
        acc += (uint32_t)((p[0] << 8) | p[1]);
        p += 2;
        n -= 2;
    }
    if (n) acc += (uint32_t)(p[0] << 8);
    while (acc >> 16) acc = (acc & 0xffff) + (acc >> 16);
    return (uint16_t)~acc;
}

static void apply(struct service *svc, int idx, int alive) {
    if (idx < 0 || idx >= svc->nbacks) return;
    struct backend *b = &svc->backs[idx];
    if (alive) {
        b->ok_cnt++;
        b->fail_cnt = 0;
        if (!b->healthy && b->ok_cnt >= HEALTH_OK_THRESHOLD) {
            b->healthy = 1;
            fprintf(stderr, "udpdist: %s: backend %s recovered (healthy)\n",
                    svc->name, b->id);
        }
    } else {
        b->fail_cnt++;
        b->ok_cnt = 0;
        if (b->healthy && b->fail_cnt >= HEALTH_FAIL_THRESHOLD) {
            b->healthy = 0;
            fprintf(stderr, "udpdist: %s: backend %s failed (unhealthy)\n",
                    svc->name, b->id);
        }
    }
}

int probe_send(struct service *svc, int i) {
    if (i < 0 || i >= svc->nbacks) return -1;
    struct backend *b = &svc->backs[i];
    uint64_t now = now_ms();

    if (b->addr.family == AF_INET) {
        if (icmp4_fd < 0) return -1;
        struct icmphdr ic;
        memset(&ic, 0, sizeof(ic));
        ic.type = ICMP_ECHO;
        ic.un.echo.id = htons((uint16_t)i);
        ic.un.echo.sequence = htons((uint16_t)i);
        ic.checksum = htons(ck16((const uint8_t *)&ic, sizeof(ic), 0));
        struct sockaddr_in sa;
        memset(&sa, 0, sizeof(sa));
        sa.sin_family = AF_INET;
        memcpy(&sa.sin_addr, b->addr.addr, 4);
        if (sendto(icmp4_fd, &ic, sizeof(ic), 0, (struct sockaddr *)&sa,
                   sizeof(sa)) <= 0) {
            apply(svc, i, 0);
            return -1;
        }
    } else {
        if (icmp6_fd < 0) return -1;
        struct icmp6_hdr ic;
        memset(&ic, 0, sizeof(ic));
        ic.icmp6_type = ICMP6_ECHO_REQUEST;
        ic.icmp6_id = htons((uint16_t)i);
        ic.icmp6_seq = htons((uint16_t)i);
        struct sockaddr_in6 sa;
        memset(&sa, 0, sizeof(sa));
        sa.sin6_family = AF_INET6;
        memcpy(&sa.sin6_addr, b->addr.addr, 16);
        sa.sin6_scope_id = b->addr.scope_id;
        if (sendto(icmp6_fd, &ic, sizeof(ic), 0, (struct sockaddr *)&sa,
                   sizeof(sa)) <= 0) {
            apply(svc, i, 0);
            return -1;
        }
    }
    pending[i] = 1;
    sent_ms[i] = now;
    return 0;
}

int health_open(struct service *svc) {
    (void)svc;
    /* A datagram ICMP socket is the unprivileged "ping socket": it needs
     * net.ipv4.ping_group_range rather than CAP_NET_RAW, so it keeps working
     * after the privilege drop. It is created here, while still root, and the
     * range is checked at reply time against the gid the process ends up with,
     * which is exactly what health_selftest() verifies below. */
    icmp4_fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP);
    if (icmp4_fd < 0) {
        fprintf(stderr, "udpdist: unprivileged ICMP socket: %s; falling back to a raw "
                        "socket, which only keeps working while privileges are held\n",
                strerror(errno));
        icmp4_fd = socket(AF_INET, SOCK_RAW, IPPROTO_ICMP);
    }
    if (icmp4_fd < 0) {
        fprintf(stderr, "udpdist: ICMP socket: %s\n", strerror(errno));
    } else {
        /* Deliberately NOT bound to the frontend address. Measured on this
         * design: a raw ICMP socket bound to the VIP receives no echo reply at
         * all, while the same socket unbound, or bound to the host's own
         * interface address, answers normally. Binding to the VIP therefore
         * looks plausible and silently destroys backend health. The probe's
         * source address does not need to be the frontend, so the kernel picks
         * it from the route, exactly as ping(8) does. */
        int fl = fcntl(icmp4_fd, F_GETFL, 0);
        fcntl(icmp4_fd, F_SETFL, fl | O_NONBLOCK);
    }

    icmp6_fd = socket(AF_INET6, SOCK_RAW, IPPROTO_ICMPV6);
    if (icmp6_fd < 0) {
        fprintf(stderr, "udpdist: ICMPv6 socket: %s\n", strerror(errno));
    } else {
        int off = 2;
        if (setsockopt(icmp6_fd, IPPROTO_IPV6, IPV6_CHECKSUM, &off, sizeof(off)) != 0)
            fprintf(stderr, "udpdist: note: this kernel does not offload the ICMPv6 "
                            "checksum (%s); v6 probe replies will fail their kernel "
                            "check\n", strerror(errno));
        int fl = fcntl(icmp6_fd, F_GETFL, 0);
        fcntl(icmp6_fd, F_SETFL, fl | O_NONBLOCK);
    }

    if (icmp4_fd < 0 && icmp6_fd < 0) {
        fprintf(stderr, "udpdist: no ICMP socket available; backend health cannot be "
                        "established. Refusing to start rather than mark every "
                        "backend down and drop all traffic.\n");
        return -1;
    }
    return 0;
}

/* Establish at startup that probing actually works, before any traffic is
 * accepted. A host with an empty net.ipv4.ping_group_range forbids unprivileged
 * ICMP, and the replies for a ping socket are matched against the gid the
 * process holds, not the one that opened it. Discovering that at the first
 * health timeout means the distributor has already marked every backend down
 * and is dropping every packet with no indication why. Measured: this host
 * ships ping_group_range "1 0", an empty range, and without this check the
 * daemon silently discarded all traffic. */
int health_selftest(struct service *svc) {
    int asked = 0, answered = 0;
    for (int i = 0; i < svc->nbacks; i++) {
        if (probe_send(svc, i) == 0) asked++;
    }
    if (!asked) return 0;

    uint64_t deadline = now_ms() + PROBE_TIMEOUT_SEC * 1000ULL;
    while (now_ms() < deadline && answered < asked) {
        struct timeval tv = {0, 50000};
        int fds[2] = {icmp4_fd, icmp6_fd};
        for (int k = 0; k < 2; k++) {
            if (fds[k] < 0) continue;
            fd_set r;
            FD_ZERO(&r);
            FD_SET(fds[k], &r);
            if (select(fds[k] + 1, &r, NULL, NULL, &tv) > 0)
                answered += health_recv(svc, fds[k]);
        }
    }
    for (int i = 0; i < svc->nbacks; i++) pending[i] = 0;
    return answered;
}

int health_fds(int fds[2]) {
    fds[0] = icmp4_fd;
    fds[1] = icmp6_fd;
    return (icmp4_fd >= 0) + (icmp6_fd >= 0);
}

void health_tick(struct service *svc) {
    uint64_t now = now_ms();
    static uint64_t last;
    if (last && now - last < HEALTH_INTERVAL_SEC * 1000ULL) return;
    last = now;
    for (int i = 0; i < svc->nbacks; i++) {
        if (pending[i]) continue;
        probe_send(svc, i);
    }
}

void health_timeout(struct service *svc) {
    uint64_t now = now_ms();
    for (int i = 0; i < svc->nbacks; i++) {
        if (!pending[i]) continue;
        if (now - sent_ms[i] >= PROBE_TIMEOUT_SEC * 1000ULL) {
            pending[i] = 0;
            apply(svc, i, 0);
        }
    }
}

static void handle(struct service *svc, const uint8_t *buf, size_t len, int v6) {
    if (v6) {
        if (len < sizeof(struct icmp6_hdr)) return;
        const struct icmp6_hdr *ic = (const struct icmp6_hdr *)buf;
        if (ic->icmp6_type != ICMP6_ECHO_REPLY) return;
        apply(svc, ntohs(ic->icmp6_seq), 1);
    } else {
        if (len < sizeof(struct icmphdr)) return;
        const struct icmphdr *ic = (const struct icmphdr *)buf;
        if (ic->type != ICMP_ECHO_REPLY) return;
        apply(svc, ntohs(ic->un.echo.sequence), 1);
    }
}

int health_recv(struct service *svc, int fd) {
    uint8_t buf[512];
    int seen = 0;
    for (;;) {
        ssize_t n = recv(fd, buf, sizeof(buf), 0);
        if (n <= 0) return seen;
        seen++;
        handle(svc, buf, (size_t)n, fd == icmp6_fd);
    }
}

void health_close(void) {
    if (icmp4_fd >= 0) close(icmp4_fd);
    if (icmp6_fd >= 0) close(icmp6_fd);
    icmp4_fd = icmp6_fd = -1;
}

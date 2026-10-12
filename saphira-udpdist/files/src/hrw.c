/* saphira-udpdist - address abstraction, hashing, rendezvous selection. BUSL-1.1, see LICENSE */
#include "udpdist.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include <time.h>
#include <arpa/inet.h>
#include <net/if.h>

uint64_t fnv1a64(const void *data, size_t len, uint64_t seed) {
    const uint8_t *p = data;
    uint64_t h = seed ? seed : 1469598103934665603ULL;
    for (size_t i = 0; i < len; i++) {
        h ^= p[i];
        h *= 1099511628211ULL;
    }
    return h;
}

uint64_t splitmix64(uint64_t x) {
    x += 0x9e3779b97f4a7c15ULL;
    x = (x ^ (x >> 30)) * 0xbf58476d1ce4e5b9ULL;
    x = (x ^ (x >> 27)) * 0x94d049bb133111ebULL;
    return x ^ (x >> 31);
}

uint64_t now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000ULL + (uint64_t)(ts.tv_nsec / 1000000);
}

int addr_parse_hostport(const char *s, struct uaddr *out) {
    char host[128];
    const char *p = strrchr(s, ':');
    uint16_t port;
    memset(out, 0, sizeof(*out));
    if (s[0] == '[') {
        const char *close = strchr(s, ']');
        if (!close || close[1] != ':') return -1;
        size_t hn = (size_t)(close - s - 1);
        if (hn >= sizeof(host)) return -1;
        memcpy(host, s + 1, hn);
        host[hn] = '\0';
        port = (uint16_t)strtoul(close + 2, NULL, 10);
        if (addr_parse(host, out) != 0) return -1;
        out->port = port;
        return 0;
    }
    if (!p) return -1;
    size_t hn = (size_t)(p - s);
    if (hn == 0 || hn >= sizeof(host)) return -1;
    memcpy(host, s, hn);
    host[hn] = '\0';
    if (host[0] == '\0') return -1;
    port = (uint16_t)strtoul(p + 1, NULL, 10);
    if (addr_parse(host, out) != 0) return -1;
    out->port = port;
    return 0;
}

int addr_parse(const char *s, struct uaddr *out) {
    struct in_addr a4;
    struct in6_addr a6;
    if (inet_pton(AF_INET, s, &a4) == 1) {
        memset(out, 0, sizeof(*out));
        out->family = AF_INET;
        memcpy(out->addr, &a4, 4);
        return 0;
    }
    if (inet_pton(AF_INET6, s, &a6) == 1) {
        memset(out, 0, sizeof(*out));
        out->family = AF_INET6;
        memcpy(out->addr, &a6, 16);
        const char *sc = strchr(s, '%');
        if (sc) out->scope_id = if_nametoindex(sc + 1);
        return 0;
    }
    return -1;
}

void addr_normalize(struct uaddr *a) {
    if (a->family != AF_INET6) return;
    static const uint8_t v4map[12] = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xff};
    if (a->addr[10] == 0xff && a->addr[11] == 0xff && memcmp(a->addr, v4map, 12) == 0) {
        a->family = AF_INET;
    }
}

void addr_format(const struct uaddr *a, char *buf, size_t len) {
    char host[INET6_ADDRSTRLEN];
    if (a->family == AF_INET) {
        inet_ntop(AF_INET, a->addr, host, sizeof(host));
        snprintf(buf, len, "%s:%u", host, a->port);
    } else {
        inet_ntop(AF_INET6, a->addr, host, sizeof(host));
        snprintf(buf, len, "[%s]:%u", host, a->port);
    }
}

void addr_id(const struct uaddr *a, char *buf, size_t len) {
    char host[INET6_ADDRSTRLEN];
    if (a->family == AF_INET) {
        inet_ntop(AF_INET, a->addr, host, sizeof(host));
        snprintf(buf, len, "%s:%u", host, a->port);
    } else {
        inet_ntop(AF_INET6, a->addr, host, sizeof(host));
        snprintf(buf, len, "%s:%u", host, a->port);
    }
}

int addr_is_multicast(const struct uaddr *a) {
    if (a->family == AF_INET) return a->addr[0] >= 224 && a->addr[0] <= 239;
    return a->addr[0] == 0xff;
}

int addr_is_broadcast(const struct uaddr *a) {
    if (a->family != AF_INET) return 0;
    return a->addr[0] == 255 && a->addr[1] == 255 && a->addr[2] == 255 && a->addr[3] == 255;
}

int mac_parse(const char *s, uint8_t out[6]) {
    unsigned v[6];
    if (sscanf(s, "%x:%x:%x:%x:%x:%x", &v[0], &v[1], &v[2], &v[3], &v[4], &v[5]) != 6)
        return -1;
    for (int i = 0; i < 6; i++) {
        if (v[i] > 255) return -1;
        out[i] = (uint8_t)v[i];
    }
    return 0;
}

void mac_format(const uint8_t mac[6], char *buf, size_t len) {
    snprintf(buf, len, "%02x:%02x:%02x:%02x:%02x:%02x",
             mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
}

int backend_compute_hash(struct backend *b) {
    size_t alen = (b->addr.family == AF_INET) ? 4 : 16;
    uint8_t key[32];
    size_t n = 0;
    memcpy(key, b->addr.addr, alen);
    n = alen;
    key[n++] = (uint8_t)(b->addr.port >> 8);
    key[n++] = (uint8_t)(b->addr.port & 0xff);
    b->hash = splitmix64(fnv1a64(key, n, 1469598103934665603ULL));
    return 0;
}

int hrw_select(struct service *svc, const struct uaddr *client,
               uint16_t sport, const struct uaddr *front, uint16_t dport) {
    uint8_t key[64];
    size_t n = 0;
    size_t clen = (client->family == AF_INET) ? 4 : 16;
    size_t flen = (front->family == AF_INET) ? 4 : 16;
    memcpy(key, client->addr, clen);
    n += clen;
    key[n++] = (uint8_t)(sport >> 8);
    key[n++] = (uint8_t)(sport & 0xff);
    key[n++] = (uint8_t)(front->family == AF_INET ? 4 : 6);
    memcpy(key + n, front->addr, flen);
    n += flen;
    key[n++] = (uint8_t)(dport >> 8);
    key[n++] = (uint8_t)(dport & 0xff);

    uint64_t fh = splitmix64(fnv1a64(key, n, 1469598103934665603ULL));

    int best = -1;
    uint64_t best_score = 0;
    for (int i = 0; i < svc->nbacks; i++) {
        struct backend *b = &svc->backs[i];
        if (!b->healthy) continue;
        /* Score is a function of backend identity and the flow only. The array
         * index must never appear here: mixing it in means a pure config
         * reorder reshuffles every later backend's score and moves live flows. */
        uint64_t s = splitmix64(b->hash ^ fh);
        if (best < 0 || s > best_score) {
            best_score = s;
            best = i;
        }
    }
    return best;
}

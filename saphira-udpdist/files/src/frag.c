/* saphira-udpdist - bounded first-fragment steering associations. BUSL-1.1, see LICENSE */
#include "udpdist.h"

#include <string.h>

#define FRAG_PROBE 64

static struct frag_assoc frag_tbl[FRAG_TABLE_SLOTS];

/* The association is keyed on the identity fragments actually share: source
 * address, destination address, protocol and the fragmentation identifier.
 * The destination address already distinguishes two VIPs, and the port is
 * deliberately absent because a non-initial fragment carries no transport
 * header, so the backend has to be recoverable without it. */
static uint64_t assoc_key(const struct l3info *ip) {
    uint8_t k[80];
    size_t n = 0;
    size_t alen = (ip->src.family == AF_INET) ? 4 : 16;
    memcpy(k, ip->src.addr, alen);
    n = alen;
    memcpy(k + n, ip->dst.addr, alen);
    n += alen;
    k[n++] = ip->proto;
    k[n++] = (uint8_t)(ip->frag_id >> 24);
    k[n++] = (uint8_t)(ip->frag_id >> 16);
    k[n++] = (uint8_t)(ip->frag_id >> 8);
    k[n++] = (uint8_t)ip->frag_id;
    return fnv1a64(k, n, 1469598103934665603ULL);
}

static int same_assoc(const struct frag_assoc *a, const struct l3info *ip) {
    size_t alen = (ip->src.family == AF_INET) ? 4 : 16;
    if (a->proto != ip->proto) return 0;
    if (a->frag_id != ip->frag_id) return 0;
    if (memcmp(a->src.addr, ip->src.addr, alen) != 0) return 0;
    if (memcmp(a->dst.addr, ip->dst.addr, alen) != 0) return 0;
    return 1;
}

void frag_expire(struct service *svc, uint64_t now) {
    (void)svc;
    for (size_t i = 0; i < FRAG_TABLE_SLOTS; i++) {
        if (frag_tbl[i].used && frag_tbl[i].expiry_ms <= now) frag_tbl[i].used = 0;
    }
}

int frag_lookup(struct service *svc, const struct l3info *ip) {
    (void)svc;
    uint64_t k = assoc_key(ip);
    uint64_t now = now_ms();
    size_t start = (size_t)(k & (FRAG_TABLE_SLOTS - 1));
    for (size_t p = 0; p < FRAG_PROBE; p++) {
        struct frag_assoc *a = &frag_tbl[(start + p) & (FRAG_TABLE_SLOTS - 1)];
        if (a->used && a->expiry_ms <= now) a->used = 0;
        if (a->used && a->key == k && same_assoc(a, ip)) {
            a->expiry_ms = now + FRAG_ASSOC_TTL_MS;
            return a->backend;
        }
    }
    return -1;
}

int frag_insert(struct service *svc, const struct l3info *ip, int backend) {
    (void)svc;
    uint64_t k = assoc_key(ip);
    uint64_t now = now_ms();
    size_t start = (size_t)(k & (FRAG_TABLE_SLOTS - 1));
    size_t freeslot = (size_t)-1;

    for (size_t p = 0; p < FRAG_PROBE; p++) {
        struct frag_assoc *a = &frag_tbl[(start + p) & (FRAG_TABLE_SLOTS - 1)];
        if (a->used && a->expiry_ms <= now) {
            a->used = 0;
            if (freeslot == (size_t)-1) freeslot = (start + p) & (FRAG_TABLE_SLOTS - 1);
            continue;
        }
        if (!a->used) {
            if (freeslot == (size_t)-1) freeslot = (start + p) & (FRAG_TABLE_SLOTS - 1);
            continue;
        }
        if (a->key == k && same_assoc(a, ip)) {
            a->expiry_ms = now + FRAG_ASSOC_TTL_MS;
            a->backend = backend;
            return 0;
        }
    }
    if (freeslot == (size_t)-1) return -1;

    struct frag_assoc *a = &frag_tbl[freeslot];
    memset(a, 0, sizeof(*a));
    a->used = 1;
    a->key = k;
    a->proto = ip->proto;
    a->frag_id = ip->frag_id;
    a->backend = backend;
    size_t alen = (ip->src.family == AF_INET) ? 4 : 16;
    memcpy(a->src.addr, ip->src.addr, alen);
    memcpy(a->dst.addr, ip->dst.addr, alen);
    a->expiry_ms = now + FRAG_ASSOC_TTL_MS;
    return 0;
}

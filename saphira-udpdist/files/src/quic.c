/* saphira-udpdist - QUIC/HTTP3 routing, QUIC-LB plaintext CIDs. BUSL-1.1, see LICENSE */
#include "udpdist.h"

#include <string.h>
#include <stdlib.h>

#define QF_PROBE 64
#define QF_MAX 20
#define QUIC_FALLBACK_CODEPOINT 7

static struct quic_fb fb_tbl[QUIC_FALLBACK_SLOTS];

const struct quic_cfg *quic_find_cfg(const struct service *svc, int config_id) {
    for (int i = 0; i < svc->nquic; i++)
        if (svc->quic[i].in_use && svc->quic[i].config_id == config_id)
            return &svc->quic[i];
    return NULL;
}

int quic_configure(struct service *svc, const struct quic_cfg *cfg) {
    if (cfg->config_id < 0 || cfg->config_id > 6) return -1;
    if (cfg->config_id == QUIC_FALLBACK_CODEPOINT) return -1;
    if (cfg->server_id_len < 1 || cfg->server_id_len > 7) return -1;
    if (cfg->server_id_len + 1 > QF_MAX) return -1;
    if (cfg->self_describing) {
        if (cfg->server_id_len + 1 > 31) return -1;
    } else {
        if (cfg->cid_len < cfg->server_id_len + 1 || cfg->cid_len > QF_MAX) return -1;
    }
    for (int i = 0; i < svc->nquic; i++) {
        if (svc->quic[i].in_use && svc->quic[i].config_id == cfg->config_id) {
            svc->quic[i] = *cfg;
            svc->quic[i].in_use = 1;
            return 0;
        }
    }
    if (svc->nquic >= UD_MAX_QUIC_CFG) return -1;
    svc->quic[svc->nquic] = *cfg;
    svc->quic[svc->nquic].in_use = 1;
    svc->nquic++;
    return 0;
}

int backend_by_sid(const struct service *svc, uint64_t sid) {
    for (int i = 0; i < svc->nbacks; i++)
        if (svc->backs[i].quic_sid_set && svc->backs[i].quic_sid == sid)
            return i;
    return -1;
}

static uint64_t read_sid(const uint8_t *p, int n) {
    uint64_t v = 0;
    for (int i = 0; i < n; i++) v = (v << 8) | p[i];
    return v;
}

void quic_classify(const uint8_t *pl, size_t len, struct service *svc,
                   int *is_quic, int *routable, uint64_t *sid) {
    *is_quic = 0;
    *routable = 0;
    *sid = 0;
    if (len < 1) return;

    uint8_t b0 = pl[0];
    if (!(b0 & 0x40)) return;

    if (b0 & 0x80) {
        /* Long header. RFC 9000 section 17.2: the Header Form bit is 1 for a
         * long header and 0 for a short one, so the long form is the one with
         * the high bit SET. Inverting this makes every long header look like a
         * short one, which no unit test written alongside the mistake can
         * catch; only a real QUIC exchange does. The DCID length is an explicit
         * field, so extraction needs no configured length. Per the
         * load-balancer draft the CID encoding is version invariant, so nothing
         * else in the header is consulted. */
        *is_quic = 1;
        if (len < 6) return;
        int type = (b0 >> 4) & 0x03;
        if (type == 3) return;
        size_t dlen = pl[5];
        if (dlen == 0) return;
        if (6 + dlen > len) return;
        const uint8_t *dcid = pl + 6;

        int cfgid = dcid[0] >> 5;
        if (cfgid == QUIC_FALLBACK_CODEPOINT) return;
        const struct quic_cfg *c = quic_find_cfg(svc, cfgid);
        if (!c) return;

        if (c->self_describing) {
            if ((size_t)(1 + (dcid[0] & 0x1f)) != dlen) return;
        } else if (dlen != (size_t)c->cid_len) {
            return;
        }
        if (dlen < (size_t)c->server_id_len + 1) return;
        *sid = read_sid(dcid + 1, c->server_id_len);
        *routable = 1;
        return;
    }

    /* Short header (RFC 9000 section 17.3): Header Form 0, Fixed Bit 1. The
     * DCID has no length field, so the length must come from configuration. The config codepoint lives in the top three bits of the
     * first CID octet, which sits immediately after the fixed one-octet prefix,
     * so the codepoint is readable before the length is known. */
    *is_quic = 1;
    if (len < 2) return;
    uint8_t dcid0 = pl[1];
    int cfgid = dcid0 >> 5;
    if (cfgid == QUIC_FALLBACK_CODEPOINT) return;
    const struct quic_cfg *c = quic_find_cfg(svc, cfgid);
    if (!c) return;

    size_t need;
    if (c->self_describing) need = 1 + (size_t)(dcid0 & 0x1f);
    else need = (size_t)c->cid_len;
    if (need < (size_t)c->server_id_len + 1) return;
    if (1 + need > len) return;
    *sid = read_sid(pl + 2, c->server_id_len);
    *routable = 1;
}

static uint64_t fb_key(const struct l3info *ip, const struct frontend *f) {
    uint8_t k[80];
    size_t n = 0;
    size_t alen = (ip->src.family == AF_INET) ? 4 : 16;
    memcpy(k, ip->src.addr, alen);
    n = alen;
    k[n++] = (uint8_t)(ip->src_port >> 8);
    k[n++] = (uint8_t)(ip->src_port & 0xff);
    size_t flen = (f->addr.family == AF_INET) ? 4 : 16;
    memcpy(k + n, f->addr.addr, flen);
    n += flen;
    k[n++] = (uint8_t)(f->addr.port >> 8);
    k[n++] = (uint8_t)(f->addr.port & 0xff);
    return fnv1a64(k, n, 1469598103934665603ULL);
}

static int fb_same(const struct quic_fb *e, const struct l3info *ip,
                   const struct frontend *f) {
    size_t alen = (ip->src.family == AF_INET) ? 4 : 16;
    size_t flen = (f->addr.family == AF_INET) ? 4 : 16;
    if (e->client.port != ip->src_port) return 0;
    if (e->front.port != f->addr.port) return 0;
    if (memcmp(e->client.addr, ip->src.addr, alen) != 0) return 0;
    if (memcmp(e->front.addr, f->addr.addr, flen) != 0) return 0;
    return 1;
}

static int fb_lookup(const struct l3info *ip, const struct frontend *f,
                     uint64_t *key, uint64_t now) {
    uint64_t k = fb_key(ip, f);
    size_t start = (size_t)(k & (QUIC_FALLBACK_SLOTS - 1));
    for (size_t p = 0; p < QF_PROBE; p++) {
        struct quic_fb *e = &fb_tbl[(start + p) & (QUIC_FALLBACK_SLOTS - 1)];
        if (e->used && e->expiry_ms <= now) e->used = 0;
        if (e->used && e->key == k && fb_same(e, ip, f)) {
            e->expiry_ms = now + QUIC_FALLBACK_TTL_MS;
            *key = k;
            return e->backend;
        }
    }
    *key = k;
    return -2;
}

static int fb_insert(const struct l3info *ip, const struct frontend *f,
                     uint64_t key, int backend, uint64_t now) {
    size_t start = (size_t)(key & (QUIC_FALLBACK_SLOTS - 1));
    size_t freeslot = (size_t)-1;
    for (size_t p = 0; p < QF_PROBE; p++) {
        struct quic_fb *e = &fb_tbl[(start + p) & (QUIC_FALLBACK_SLOTS - 1)];
        if (e->used && e->expiry_ms <= now) {
            e->used = 0;
            if (freeslot == (size_t)-1) freeslot = (start + p) & (QUIC_FALLBACK_SLOTS - 1);
            continue;
        }
        if (!e->used) {
            if (freeslot == (size_t)-1) freeslot = (start + p) & (QUIC_FALLBACK_SLOTS - 1);
            continue;
        }
    }
    if (freeslot == (size_t)-1) return -1;
    struct quic_fb *e = &fb_tbl[freeslot];
    memset(e, 0, sizeof(*e));
    e->used = 1;
    e->key = key;
    e->client = ip->src;
    e->client.port = ip->src_port;
    e->front = f->addr;
    e->backend = backend;
    e->expiry_ms = now + QUIC_FALLBACK_TTL_MS;
    return 0;
}

void quic_fb_expire(struct service *svc, uint64_t now) {
    (void)svc;
    for (size_t i = 0; i < QUIC_FALLBACK_SLOTS; i++)
        if (fb_tbl[i].used && fb_tbl[i].expiry_ms <= now) fb_tbl[i].used = 0;
}

int quic_select(struct service *svc, struct frontend *f, const struct l3info *ip,
                int *state) {
    uint64_t now = now_ms();

    if (f->quic_mode == QUIC_MODE_QUIC_LB) {
        int is_quic = 0, routable = 0;
        uint64_t sid = 0;
        quic_classify(ip->payload, ip->payload_len, svc, &is_quic, &routable, &sid);
        if (is_quic && routable) {
            int b = backend_by_sid(svc, sid);
            if (b >= 0) {
                if (!svc->backs[b].healthy) {
                    /* A different server does not hold this connection's state
                     * and would reject the CID. Dropping is the honest outcome,
                     * and re-routing it would be a lie. */
                    svc->st.quic_backend_down++;
                    f->quic_backend_down++;
                    return -1;
                }
                svc->st.quic_routable++;
                f->quic_routable++;
                *state = QUIC_STATE_LB;
                return b;
            }
            /* The configuration matched but the server id names no active
             * backend. This is the normal case for a client-generated
             * connection id that happens to carry a live codepoint, and the
             * specification requires a fallback rather than a drop: discarding
             * it would lose real handshakes. Measured at twelve datagrams in
             * the first interoperability run. */
            svc->st.quic_backend_unknown++;
            f->quic_backend_unknown++;
        }
        if (is_quic) {
            svc->st.quic_unroutable++;
            f->quic_unroutable++;
        }
    }

    uint64_t key = 0;
    int b = fb_lookup(ip, f, &key, now);
    if (b == -2) {
        b = hrw_select(svc, &ip->src, ip->src_port, &f->addr, ip->dst_port);
        if (b < 0) return -1;
        if (fb_insert(ip, f, key, b, now) != 0) {
            b = hrw_select(svc, &ip->src, ip->src_port, &f->addr, ip->dst_port);
            if (b < 0) return -1;
        }
        svc->st.quic_fallback_miss++;
        f->quic_fallback_miss++;
        *state = QUIC_STATE_FB;
        return b;
    }
    if (b < 0) return -1;
    if (!svc->backs[b].healthy) {
        svc->st.quic_backend_down++;
        f->quic_backend_down++;
        return -1;
    }
    svc->st.quic_fallback_hit++;
    f->quic_fallback_hit++;
    *state = QUIC_STATE_FB;
    return b;
}

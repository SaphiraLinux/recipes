/* saphira-udpdist rootless unit tests. BUSL-1.1, see LICENSE */
#include "../src/udpdist.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <arpa/inet.h>
#include <linux/netlink.h>
#include <linux/rtnetlink.h>
#include <linux/neighbour.h>

struct ndmsg_ext {
    uint16_t ndm_pad;
    uint16_t ndm_ifindex_high;
};
#ifndef NDA_STATE
#define NDA_STATE 7
#endif

static int tests, failures;
static const char *group = "";

static void ok(int cond, const char *what) {
    tests++;
    if (!cond) {
        failures++;
        printf("  FAIL [%s] %s\n", group, what);
    }
}

static void okrc(int got, int want, const char *what) {
    tests++;
    if (got != want) {
        failures++;
        printf("  FAIL [%s] %s (returned %d, wanted %d)\n", group, what, got, want);
    }
}

static void g(const char *name) { group = name; printf("== %s\n", name); }

static uint16_t ck(const uint8_t *p, size_t n) {
    uint32_t acc = 0;
    while (n > 1) { acc += (uint32_t)((p[0] << 8) | p[1]); p += 2; n -= 2; }
    if (n) acc += (uint32_t)(p[0] << 8);
    while (acc >> 16) acc = (acc & 0xffff) + (acc >> 16);
    return (uint16_t)~acc;
}

static uint32_t rawsum(const uint8_t *p, size_t n) {
    uint32_t acc = 0;
    while (n > 1) { acc += (uint32_t)((p[0] << 8) | p[1]); p += 2; n -= 2; }
    if (n) acc += (uint32_t)(p[0] << 8);
    return acc;
}

static uint16_t finish(uint32_t acc) {
    while (acc >> 16) acc = (acc & 0xffff) + (acc >> 16);
    return (uint16_t)~acc;
}

static size_t eth(uint8_t *b, uint16_t etype) {
    memset(b, 0, 14);
    for (int i = 0; i < 6; i++) { b[i] = 0x02; b[6 + i] = 0x03; }
    b[12] = (uint8_t)(etype >> 8);
    b[13] = (uint8_t)(etype & 0xff);
    return 14;
}

static size_t v4hdr(uint8_t *b, const char *src, const char *dst, size_t payload,
                    uint16_t fragf, uint16_t ipid) {
    b[0] = 0x45;
    b[1] = 0;
    b[2] = (uint8_t)(((20 + payload) >> 8) & 0xff);
    b[3] = (uint8_t)((20 + payload) & 0xff);
    b[4] = (uint8_t)(ipid >> 8);
    b[5] = (uint8_t)(ipid & 0xff);
    b[6] = (uint8_t)(fragf >> 8);
    b[7] = (uint8_t)(fragf & 0xff);
    b[8] = 64;
    b[9] = IPPROTO_UDP;
    inet_pton(AF_INET, src, &b[12]);
    inet_pton(AF_INET, dst, &b[16]);
    return 20;
}

static void v4udp(uint8_t *b, const char *src, const char *dst, uint16_t sport,
                  uint16_t dport, const uint8_t *pl, size_t pln) {
    size_t o = eth(b, 0x0800);
    o += v4hdr(b + o, src, dst, 8 + pln, 0, 0x1234);
    uint8_t *u = b + o;
    u[0] = (uint8_t)(sport >> 8); u[1] = (uint8_t)(sport & 0xff);
    u[2] = (uint8_t)(dport >> 8); u[3] = (uint8_t)(dport & 0xff);
    u[4] = (uint8_t)((8 + pln) >> 8); u[5] = (uint8_t)((8 + pln) & 0xff);
    u[6] = 0; u[7] = 0;
    if (pln) memcpy(u + 8, pl, pln);
    uint8_t pseudo[12];
    memcpy(pseudo, b + o - 20 + 12, 4);
    memcpy(pseudo + 4, b + o - 20 + 16, 4);
    pseudo[8] = 0; pseudo[9] = IPPROTO_UDP;
    pseudo[10] = (uint8_t)((8 + pln) >> 8); pseudo[11] = (uint8_t)((8 + pln) & 0xff);
    uint32_t acc = rawsum(pseudo, 12) + rawsum(u, 8 + pln);
    uint16_t want = finish(acc);
    u[6] = (uint8_t)(want >> 8); u[7] = (uint8_t)(want & 0xff);
}

static size_t v6hdr(uint8_t *b, const char *src, const char *dst, uint8_t next,
                    size_t payload) {
    b[0] = 0x60;
    b[1] = b[2] = b[3] = 0;
    b[4] = (uint8_t)(payload >> 8);
    b[5] = (uint8_t)(payload & 0xff);
    b[6] = next;
    b[7] = 64;
    inet_pton(AF_INET6, src, &b[8]);
    inet_pton(AF_INET6, dst, &b[24]);
    return 40;
}

static void v6udp(uint8_t *b, const char *src, const char *dst, uint16_t sport,
                  uint16_t dport, const uint8_t *pl, size_t pln) {
    size_t o = eth(b, 0x86dd);
    o += v6hdr(b + o, src, dst, IPPROTO_UDP, 8 + pln);
    uint8_t *u = b + o;
    u[0] = (uint8_t)(sport >> 8); u[1] = (uint8_t)(sport & 0xff);
    u[2] = (uint8_t)(dport >> 8); u[3] = (uint8_t)(dport & 0xff);
    u[4] = (uint8_t)((8 + pln) >> 8); u[5] = (uint8_t)((8 + pln) & 0xff);
    u[6] = 0; u[7] = 0;
    if (pln) memcpy(u + 8, pl, pln);
    uint8_t pseudo[40];
    memcpy(pseudo, b + o - 40 + 8, 16);
    memcpy(pseudo + 16, b + o - 40 + 24, 16);
    pseudo[32] = (uint8_t)((8 + pln) >> 24);
    pseudo[33] = (uint8_t)((8 + pln) >> 16);
    pseudo[34] = (uint8_t)((8 + pln) >> 8);
    pseudo[35] = (uint8_t)(8 + pln);
    pseudo[36] = pseudo[37] = pseudo[38] = 0;
    pseudo[39] = IPPROTO_UDP;
    uint32_t acc = rawsum(pseudo, 40) + rawsum(u, 8 + pln);
    uint16_t want = finish(acc);
    u[6] = (uint8_t)(want >> 8); u[7] = (uint8_t)(want & 0xff);
}

static void t_parser(void) {
    g("frame parser");
    uint8_t b[4096];
    struct dgram d;
    const uint8_t pl[] = "hello";

    size_t n = 0;
    v4udp(b, "10.0.0.1", "10.0.0.2", 1234, 53, pl, 5);
    n = 14 + 20 + 13;
    ok(frame_parse(b, n, 9000, 1, &d) == 0, "valid IPv4/UDP accepted");
    ok(d.ip.family == AF_INET, "family is AF_INET");
    ok(d.ip.src_port == 1234 && d.ip.dst_port == 53, "ports recovered");
    ok(d.ip.payload_len == 5, "payload length");
    ok(d.ip.frag == FRAG_NONE, "not a fragment");

    v4udp(b, "10.0.0.1", "10.0.0.2", 1234, 53, pl, 5);
    b[n - 3] ^= 0xff;
    ok(frame_parse(b, n, 9000, 1, &d) != 0, "corrupt IPv4 UDP checksum rejected");

    ok(frame_parse(b, n - 4, 9000, 1, &d) == -2, "truncated capture rejected");

    n = eth(b, 0x0800);
    v4udp(b, "10.0.0.1", "224.0.0.1", 1234, 53, pl, 5);
    ok(frame_parse(b, n + 20 + 13, 9000, 1, &d) == -7, "multicast destination rejected");

    n = eth(b, 0x0800);
    v4udp(b, "10.0.0.1", "255.255.255.255", 1234, 53, pl, 5);
    ok(frame_parse(b, n + 20 + 13, 9000, 1, &d) == -8, "broadcast destination rejected");

    n = eth(b, 0x0800);
    v4udp(b, "10.0.0.1", "10.0.0.2", 1234, 53, pl, 5);
    ok(frame_parse(b, n + 20 + 13, 4, 1, &d) == -5, "oversize datagram rejected");

    n = eth(b, 0x0800);
    v4udp(b, "10.0.0.1", "10.0.0.2", 1234, 53, pl, 5);
    b[14 + 6] = 0x20; b[14 + 7] = 0x00;
    ok(frame_parse(b, n + 20 + 13, 9000, 1, &d) == 0 && d.ip.frag == FRAG_INITIAL,
       "more-fragments set is an initial fragment");

    n = eth(b, 0x0800);
    v4udp(b, "10.0.0.1", "10.0.0.2", 1234, 53, pl, 5);
    b[14 + 6] = 0x00; b[14 + 7] = 0x10;
    ok(frame_parse(b, n + 20 + 13, 9000, 1, &d) == 0 && d.ip.frag == FRAG_SUBSEQUENT,
       "non-zero fragment offset is a subsequent fragment");

    v6udp(b, "fd00::1", "fd00::2", 4000, 443, pl, 5);
    n = 14 + 40 + 13;
    ok(frame_parse(b, n, 9000, 1, &d) == 0, "valid IPv6/UDP accepted");
    ok(d.ip.src_port == 4000 && d.ip.dst_port == 443, "IPv6 ports recovered");
    b[n - 3] ^= 0xff;
    ok(frame_parse(b, n, 9000, 1, &d) != 0, "corrupt IPv6 UDP checksum rejected");

    {
        size_t o = eth(b, 0x86dd);
        o += v6hdr(b + o, "fd00::1", "fd00::2", 0, 8 + 13);
        b[o] = IPPROTO_UDP;
        b[o + 1] = 0;
        o += 8;
        uint8_t *u = b + o;
        u[0] = 0; u[1] = 0x0f; u[2] = 0x01; u[3] = 0xbb; u[4] = 0; u[5] = 13;
        memcpy(u + 8, pl, 5);
        u[6] = 0; u[7] = 0;
        uint8_t ps[40];
        memcpy(ps, b + 14 + 8, 16);
        memcpy(ps + 16, b + 14 + 24, 16);
        ps[32] = ps[33] = 0; ps[34] = 0; ps[35] = 13;
        ps[36] = ps[37] = ps[38] = 0; ps[39] = IPPROTO_UDP;
        uint32_t acc = rawsum(ps, 40) + rawsum(u, 13);
        uint16_t want = finish(acc);
        u[6] = (uint8_t)(want >> 8); u[7] = (uint8_t)(want & 0xff);
        okrc(frame_parse(b, o + 13, 9000, 1, &d), 0, "IPv6 hop-by-hop extension header walked");
    }

    {
        uint8_t inner[128];
        size_t ihl = 20 + 13;
        eth(inner, 0x0800);
        v4udp(inner, "10.0.0.1", "10.0.0.2", 1234, 53, pl, 5);
        n = eth(b, 0x8100);
        b[14] = 0; b[15] = 0x64; b[16] = 0x08; b[17] = 0x00;
        memcpy(b + 18, inner + 14, ihl);
        okrc(frame_parse(b, 18 + ihl, 9000, 1, &d), 0, "802.1Q VLAN tag handled");
        ok(d.l2_len == 18, "L2 offset past the VLAN tag");
    }

    n = eth(b, 0x0806);
    ok(frame_parse(b, n + 28, 9000, 1, &d) == -3, "non-IP ethertype rejected");
}

static void build_svc(struct service *s, int n) {
    memset(s, 0, sizeof(*s));
    s->max_datagram = MAX_DATAGRAM_DEFAULT;
    s->nifaces = 1;
    snprintf(s->ifaces[0].name, UD_IFNAME_MAX, "lo");
    for (int i = 0; i < n; i++) {
        struct backend *b = &s->backs[i];
        snprintf(b->id, sizeof(b->id), "10.0.0.%d:9000", 11 + i);
        b->addr.family = AF_INET;
        b->addr.addr[3] = (uint8_t)(11 + i);
        b->addr.port = 9000;
        b->healthy = 1;
        backend_compute_hash(b);
    }
    s->nbacks = n;
}

static void t_hrw(void) {
    g("rendezvous selection");
    struct service a, b, c;
    build_svc(&a, 3);
    b = a; c = a;
    struct backend t;
    t = b.backs[0]; b.backs[0] = b.backs[2]; b.backs[2] = t;
    t = c.backs[0]; c.backs[0] = c.backs[1]; c.backs[1] = c.backs[2]; c.backs[2] = t;

    int same = 1, spread[8] = {0};
    for (int i = 0; i < 200; i++) {
        struct uaddr cl;
        memset(&cl, 0, sizeof(cl));
        cl.family = AF_INET;
        cl.addr[0] = 10; cl.addr[2] = (uint8_t)(1 + i / 250);
        cl.addr[3] = (uint8_t)(i % 250);
        struct uaddr fr;
        memset(&fr, 0, sizeof(fr));
        fr.family = AF_INET;
        fr.addr[3] = 2;
        fr.port = 53;
        int i1 = hrw_select(&a, &cl, 1000, &fr, 53);
        int i2 = hrw_select(&b, &cl, 1000, &fr, 53);
        int i3 = hrw_select(&c, &cl, 1000, &fr, 53);
        if (i1 < 0) { same = 0; break; }
        if (strcmp(a.backs[i1].id, b.backs[i2].id) != 0) same = 0;
        if (strcmp(a.backs[i1].id, c.backs[i3].id) != 0) same = 0;
        spread[i1]++;
    }
    ok(same, "200/200 flows stable across three config orderings");
    ok(spread[0] > 20 && spread[1] > 20 && spread[2] > 20, "all three backends receive traffic");

    struct service d = a;
    d.backs[1].healthy = 0;
    int moved = 0, survivor_changed = 0;
    for (int i = 0; i < 200; i++) {
        struct uaddr cl, fr;
        memset(&cl, 0, sizeof(cl)); memset(&fr, 0, sizeof(fr));
        cl.family = AF_INET; fr.family = AF_INET;
        cl.addr[0] = 10; cl.addr[2] = 1; cl.addr[3] = (uint8_t)(i % 250);
        fr.addr[3] = 2; fr.port = 53;
        int before = hrw_select(&a, &cl, 1000, &fr, 53);
        int after = hrw_select(&d, &cl, 1000, &fr, 53);
        if (strcmp(a.backs[before].id, a.backs[1].id) == 0) moved++;
        else if (strcmp(a.backs[before].id, d.backs[after].id) != 0) survivor_changed++;
    }
    ok(moved > 0, "removing a backend moves some flows");
    ok(survivor_changed == 0, "no survivor flow moves when a backend is removed");

    /* A single client sending many consecutive source ports must still spread.
     * One client is a single hash input, so this is the worst case for
     * rendezvous hashing and the case most likely to hide a weak score. */
    {
        struct service e = a;
        int d[UD_MAX_BACKENDS] = {0};
        for (int i = 0; i < 200; i++) {
            struct uaddr c, f;
            memset(&c, 0, sizeof(c)); memset(&f, 0, sizeof(f));
            c.family = AF_INET; c.addr[0] = 198; c.addr[1] = 51;
            c.addr[2] = 100; c.addr[3] = 100;
            f.family = AF_INET; f.addr[0] = 198; f.addr[1] = 51;
            f.addr[2] = 100; f.addr[3] = 10; f.port = 443;
            d[hrw_select(&e, &c, (uint16_t)(47000 + i), &f, 443)]++;
        }
        int lo = 200, hi = 0, all = 0;
        for (int k = 0; k < e.nbacks; k++) {
            printf("  distribution over 200 consecutive ports: backend %d got %d\n",
                   k + 1, d[k]);
            if (d[k] < lo) lo = d[k];
            if (d[k] > hi) hi = d[k];
            all += d[k];
        }
        ok(all == 200, "every one of the 200 flows was assigned");
        ok(lo > 20, "no backend was starved of a single client's traffic");
        ok(hi - lo < 90, "one client's flows are not piling onto a single backend");
    }

    /* The same flows replayed must land identically: this is what makes a
     * reorder check meaningful and what a QUIC handshake relies on. */
    {
        struct service e = a;
        int first[8], second[8];
        struct uaddr c, f;
        memset(&c, 0, sizeof(c)); memset(&f, 0, sizeof(f));
        c.family = AF_INET; c.addr[3] = 100;
        f.family = AF_INET; f.addr[3] = 10; f.port = 443;
        for (int i = 0; i < 8; i++)
            first[i] = hrw_select(&e, &c, (uint16_t)(47000 + i), &f, 443);
        for (int i = 0; i < 8; i++)
            second[i] = hrw_select(&e, &c, (uint16_t)(47000 + i), &f, 443);
        int same = 1;
        for (int i = 0; i < 8; i++) if (first[i] != second[i]) same = 0;
        ok(same, "replaying the same flows reproduces the same backends");
    }
}

static void t_quic(void) {
    g("QUIC classification");
    struct service s;
    build_svc(&s, 2);
    s.nquic = 0;
    struct quic_cfg c = {0};
    c.config_id = 2; c.cid_len = 8; c.server_id_len = 2; c.self_describing = 0;
    ok(quic_configure(&s, &c) == 0, "quic_config accepted");
    c.config_id = 7; c.self_describing = 0; c.cid_len = 8;
    ok(quic_configure(&s, &c) == -1, "config codepoint 0b111 refused");
    c.config_id = 0; c.self_describing = 1; c.cid_len = 0; c.server_id_len = 2;
    ok(quic_configure(&s, &c) == 0, "self-describing config accepted");

    int isq, rout;
    uint64_t sid;
    uint8_t longpkt[64];
    longpkt[0] = 0xC0;   /* Header Form 1, Fixed 1, type 00 = Initial */
    longpkt[1] = 0; longpkt[2] = 0; longpkt[3] = 0; longpkt[4] = 1;
    longpkt[5] = 8;
    longpkt[6] = (2 << 5) | 0x00;
    longpkt[7] = 0x00; longpkt[8] = 0x07;
    quic_classify(longpkt, 64, &s, &isq, &rout, &sid);
    ok(isq && rout, "long header with a configured CID is routable");
    ok(sid == 7, "plaintext server id extracted");

    longpkt[5] = 4;
    quic_classify(longpkt, 64, &s, &isq, &rout, &sid);
    ok(isq && !rout, "short CID for a fixed-length config is unroutable");

    longpkt[5] = 8;
    longpkt[6] = (7 << 5);
    quic_classify(longpkt, 64, &s, &isq, &rout, &sid);
    ok(isq && !rout, "config codepoint 0b111 is unroutable");

    longpkt[6] = (3 << 5);
    quic_classify(longpkt, 64, &s, &isq, &rout, &sid);
    ok(isq && !rout, "unknown config codepoint is unroutable");

    uint8_t shortpkt[64];
    shortpkt[0] = 0x40 | 0x03;  /* Header Form 0, Fixed 1 */
    shortpkt[1] = (2 << 5) | 0x00;
    shortpkt[2] = 0x00; shortpkt[3] = 0x07;
    quic_classify(shortpkt, 64, &s, &isq, &rout, &sid);
    ok(isq && rout, "short header with a configured length is routable");
    ok(sid == 7, "short header server id extracted");

    shortpkt[1] = (0 << 5) | 0x06;
    shortpkt[2] = 0x00; shortpkt[3] = 0x09;
    quic_classify(shortpkt, 64, &s, &isq, &rout, &sid);
    ok(isq && rout, "self-describing short header is routable");
    ok(sid == 9, "self-describing server id extracted");

    shortpkt[1] = (2 << 5) | 0x00;
    quic_classify(shortpkt, 3, &s, &isq, &rout, &sid);
    ok(isq && !rout, "truncated short header is unroutable, never guessed");

    uint8_t notquic[64];
    memset(notquic, 0, sizeof(notquic));
    notquic[0] = 0x00;
    quic_classify(notquic, 64, &s, &isq, &rout, &sid);
    ok(!isq, "fixed bit clear is not QUIC");

    g("QUIC selection policy");
    struct service q;
    build_svc(&q, 2);
    struct quic_cfg qc = {0};
    qc.config_id = 2; qc.cid_len = 8; qc.server_id_len = 2;
    quic_configure(&q, &qc);
    q.backs[0].quic_sid = 0x0102; q.backs[0].quic_sid_set = 1;
    q.backs[1].quic_sid = 0x0304; q.backs[1].quic_sid_set = 1;

    struct frontend f;
    memset(&f, 0, sizeof(f));
    f.proto = FRONT_PROTO_QUIC;
    f.quic_mode = QUIC_MODE_QUIC_LB;
    f.addr.family = AF_INET;
    f.addr.addr[3] = 2;
    f.addr.port = 443;

    struct l3info ip;
    memset(&ip, 0, sizeof(ip));
    ip.src.family = AF_INET; ip.src.addr[0] = 10; ip.src.addr[3] = 1; ip.src_port = 40000;
    ip.dst = f.addr; ip.dst_port = 443;
    uint8_t pkt[64];
    pkt[0] = 0x40 | 0x03;
    pkt[1] = (2 << 5); pkt[2] = 0x03; pkt[3] = 0x04;
    ip.payload = pkt; ip.payload_len = 64;

    int st = 0;
    int b1 = quic_select(&q, &f, &ip, &st);
    ok(b1 == 1, "routable CID selects the backend named by the server id");
    ok(st == QUIC_STATE_LB, "state reported as QUIC-LB");

    q.backs[1].healthy = 0;
    int b2 = quic_select(&q, &f, &ip, &st);
    ok(b2 < 0, "a dead backend is never silently remapped for QUIC");
    ok(q.st.quic_backend_down == 1, "backend-down is counted");

    q.backs[1].healthy = 1;
    uint8_t unr[64];
    memset(unr, 0, sizeof(unr));
    unr[0] = 0xC0; unr[5] = 8; unr[6] = (7 << 5);
    ip.payload = unr; ip.payload_len = 64;
    int s1 = 0;
    int b3 = quic_select(&q, &f, &ip, &s1);
    ok(b3 >= 0, "an unroutable CID still forwards via fallback");
    ok(s1 == QUIC_STATE_FB, "state reported as fallback, not QUIC-LB");
    uint64_t before = q.st.quic_fallback_miss;
    quic_select(&q, &f, &ip, &s1);
    ok(q.st.quic_fallback_hit == 1, "the fallback affinity is sticky for the same tuple");
    ok(q.st.quic_fallback_miss == before, "a repeat does not create a new entry");

    struct uaddr other = ip.src;
    other.addr[3] = 9;
    struct l3info ip2 = ip;
    ip2.src = other;
    int s2 = 0;
    quic_select(&q, &f, &ip2, &s2);
    ok(q.st.quic_fallback_miss == before + 1, "a different tuple takes its own decision");
}

static void t_frag(void) {
    g("fragment associations");
    struct service s;
    build_svc(&s, 1);
    struct l3info ip;
    memset(&ip, 0, sizeof(ip));
    ip.src.family = AF_INET; ip.src.addr[0] = 10; ip.src.addr[3] = 7;
    ip.dst.family = AF_INET; ip.dst.addr[3] = 2;
    ip.proto = IPPROTO_UDP;
    ip.frag_id = 0xbeef;
    ok(frag_insert(&s, &ip, 1) == 0, "initial fragment association stored");
    ok(frag_lookup(&s, &ip) == 1, "the association returns the chosen backend");
    struct l3info ip2 = ip;
    ip2.frag_id = 0xbeee;
    ok(frag_lookup(&s, &ip2) < 0, "a different datagram does not match");
    ip2 = ip;
    ip2.dst.addr[3] = 9;
    ok(frag_lookup(&s, &ip2) < 0, "a different destination does not match");
    ip2 = ip;
    ip2.src.addr[3] = 8;
    ok(frag_lookup(&s, &ip2) < 0, "a different source does not match");
}

static void t_addr(void) {
    g("address handling");
    struct uaddr a;
    ok(addr_parse_hostport("10.0.0.1:53", &a) == 0 && a.family == AF_INET && a.port == 53,
       "IPv4 host:port");
    ok(addr_parse_hostport("[fd00::1]:443", &a) == 0 && a.family == AF_INET6 && a.port == 443,
       "bracketed IPv6 host:port");
    ok(addr_parse_hostport("nonsense", &a) != 0, "garbage rejected");
    ok(addr_parse_hostport("10.0.0.1", &a) != 0, "missing port rejected");
    ok(addr_parse_hostport("10.0.0.1:0", &a) == 0, "port zero parses (rejected in config)");
    uint8_t m[6];
    ok(mac_parse("aa:bb:cc:dd:ee:ff", m) == 0 && m[0] == 0xaa && m[5] == 0xff, "mac parse");
    ok(mac_parse("zz:bb:cc:dd:ee:ff", m) != 0, "bad mac rejected");

    g("service name charset");
    ok(name_is_valid("svc-1_x"), "plain name accepted");
    const char *bad[] = {"a b", "a;b", "a$b", "a`b", "a|b", "a&b", "a.b/c", "..",
                         "a\nb", "*", "", NULL};
    for (int i = 0; bad[i]; i++) {
        char w[32];
        snprintf(w, sizeof(w), "%s", bad[i]);
        if (!name_is_valid(w)) continue;
        printf("  FAIL [service name charset] accepted %s\n", w);
        failures++;
    }
    tests++;
}

static void write_cfg(const char *path, const char *body) {
    FILE *f = fopen(path, "w");
    if (!f) { perror(path); exit(1); }
    fputs(body, f);
    fclose(f);
}

static void t_config(void) {
    g("configuration validation");
    char p[256];
    struct service s;

    snprintf(p, sizeof(p), "/tmp/ud-test-ok.conf");
    write_cfg(p, "# comment\n; also a comment\n"
                 "frontend=10.0.0.2:53 iface=lo proto=udp\n"
                 "backend=10.0.0.11:9000 mac=aa:bb:cc:00:00:01\n"
                 "backend=10.0.0.12:9000 mac=aa:bb:cc:00:00:02\n"
                 "max_datagram=1500\n");
    ok(config_load(p, &s, "t") == 0, "a valid configuration loads");
    ok(s.nfronts == 1 && s.nbacks == 2, "frontends and backends counted");

    write_cfg(p, "frontend=10.0.0.2:53\nbackend=10.0.0.11:9000\nfrontend=10.0.0.2:53\n");
    ok(config_load(p, &s, "t") != 0, "duplicate frontend refused");

    write_cfg(p, "frontend=10.0.0.2:53\nbackend=10.0.0.11:9000\nfrobnicate=1\n");
    ok(config_load(p, &s, "t") != 0, "unknown key refused");

    write_cfg(p, "frontend=10.0.0.2:53\nbackend=10.0.0.11:9000\nbackend=10.0.0.11:9000\n");
    ok(config_load(p, &s, "t") != 0, "duplicate backend refused");

    write_cfg(p, "frontend=10.0.0.2:53\n");
    ok(config_load(p, &s, "t") != 0, "no backends refused");

    write_cfg(p, "backend=10.0.0.11:9000\n");
    ok(config_load(p, &s, "t") != 0, "no frontends refused");

    {
        char body[8192];
        int n = snprintf(body, sizeof(body), "frontend=10.0.0.2:53\nbackend=10.0.0.11:9000\n");
        for (int i = 0; i < 4000 && n < (int)sizeof(body) - 1; i++)
            body[n++] = 'x';
        body[n] = '\0';
        write_cfg(p, body);
        ok(config_load(p, &s, "t") != 0, "an over-long line is refused, not split");
    }

    write_cfg(p, "frontend=10.0.0.2:53 proto=quic quic_mode=quic_lb\n"
                 "backend=10.0.0.11:9000 mac=aa:bb:cc:00:00:01\n");
    ok(config_load(p, &s, "t") != 0,
       "quic_lb without a CID configuration fails validation instead of degrading");

    write_cfg(p, "frontend=10.0.0.2:53 proto=quic quic_mode=fallback\n"
                 "backend=10.0.0.11:9000 mac=aa:bb:cc:00:00:01\n");
    ok(config_load(p, &s, "t") == 0, "quic fallback needs no server cooperation");

    write_cfg(p, "frontend=10.0.0.2:53 proto=quic quic_mode=quic_lb\n"
                 "quic_config=2 cid_len=8 server_id_len=2\n"
                 "backend=10.0.0.11:9000 mac=aa:bb:cc:00:00:01\n");
    ok(config_load(p, &s, "t") != 0, "a QUIC-LB backend without a server id is refused");

    write_cfg(p, "frontend=10.0.0.2:53 proto=quic quic_mode=quic_lb\n"
                 "quic_config=2 cid_len=8 server_id_len=2\n"
                 "backend=10.0.0.11:9000 mac=aa:bb:cc:00:00:01 sid=1\n"
                 "backend=10.0.0.12:9000 mac=aa:bb:cc:00:00:02 sid=1\n");
    ok(config_load(p, &s, "t") != 0, "duplicate server ids are refused");

    write_cfg(p, "frontend=10.0.0.2:53 proto=quic quic_mode=quic_lb\n"
                 "quic_config=2 cid_len=8 server_id_len=2\n"
                 "backend=10.0.0.11:9000 mac=aa:bb:cc:00:00:01 sid=1\n"
                 "backend=10.0.0.12:9000 mac=aa:bb:cc:00:00:02 sid=2\n");
    ok(config_load(p, &s, "t") == 0, "a complete QUIC-LB configuration loads");

    write_cfg(p, "frontend=10.0.0.2:53\nbackend=10.0.0.11:9000\nrequire_mac=1\n");
    ok(config_load(p, &s, "t") != 0, "require_mac rejects a backend with no mac");

    write_cfg(p, "frontend=10.0.0.2:53\nbackend=10.0.0.11:9000 mac=not-a-mac\n");
    ok(config_load(p, &s, "t") != 0, "a malformed mac is refused");

    write_cfg(p, "frontend=10.0.0.2:53 iface=lo\nbackend=10.0.0.11:9000\n");
    ok(config_load(p, &s, "t") == 0, "iface= is accepted");
    write_cfg(p, "frontend=10.0.0.2:53 iface=lo proto=quic\nbackend=10.0.0.11:9000\n");
    ok(config_load(p, &s, "t") == 0, "proto=quic without quic_mode defaults to fallback");
    write_cfg(p, "frontend=10.0.0.2:53 iface=lo\nbackend=10.0.0.11:9000 mac=aa:bb:cc:dd:ee:ff\n"
                 "backend=10.0.0.12:9000 mac=aa:bb:cc:dd:ee:f0\n");
    ok(config_load(p, &s, "t") == 0, "two backends with macs");
    remove(p);
}


/* Build a synthetic neighbour message. Real kernel replies always carry the
 * ndmsg_ext, but the payload does not record its presence, so both forms are
 * constructed to prove the parser handles either without being told which. */
static size_t build_neigh_msg(char *buf, int family, const void *dst, int dstlen,
                              const uint8_t mac[6], uint16_t state, int ifindex,
                              int with_ext, int omit_lladdr) {
    struct nlmsghdr *nlh = (struct nlmsghdr *)buf;
    struct ndmsg *nd = (struct ndmsg *)NLMSG_DATA(nlh);
    struct rtattr *rta;
    size_t base;

    memset(buf, 0, 512);
    nlh->nlmsg_type = RTM_NEWNEIGH;
    nd->ndm_family = (uint8_t)family;
    nd->ndm_ifindex = ifindex;
    nd->ndm_state = state;

    base = NLMSG_LENGTH(sizeof(struct ndmsg));
    if (with_ext) {
        struct ndmsg_ext *nde = (struct ndmsg_ext *)((char *)nd + NLMSG_ALIGN(sizeof(*nd)));
        nde->ndm_ifindex_high = 0;
        base += NLMSG_ALIGN(sizeof(struct ndmsg_ext));
    }
    rta = (struct rtattr *)(buf + base);
    rta->rta_type = NDA_DST;
    rta->rta_len = (unsigned short)RTA_LENGTH((unsigned)dstlen);
    memcpy(RTA_DATA(rta), dst, (size_t)dstlen);
    base += RTA_ALIGN(RTA_LENGTH((unsigned)dstlen));
    if (!omit_lladdr) {
        rta = (struct rtattr *)(buf + base);
        rta->rta_type = NDA_LLADDR;
        rta->rta_len = (unsigned short)RTA_LENGTH(6);
        memcpy(RTA_DATA(rta), mac, 6);
        base += RTA_ALIGN(RTA_LENGTH(6));
    }
    nlh->nlmsg_len = (uint32_t)base;
    return base;
}

static void t_neigh(void) {
    char buf[512];
    struct neigh_entry e;
    struct in_addr a4;
    uint8_t mac[6] = {0x52, 0x54, 0x00, 0xaa, 0x01, 0x0b};
    struct in6_addr a6;

    group = "neighbour";
    inet_pton(AF_INET, "10.0.0.11", &a4);
    inet_pton(AF_INET6, "2001:db8::11", &a6);

    /* the form the kernel actually sends: short and long both must parse */
    for (int ext = 0; ext < 2; ext++) {
        build_neigh_msg(buf, AF_INET, &a4, 4, mac, NUD_REACHABLE, 2, ext, 0);
        ok(neigh_parse((struct nlmsghdr *)buf, &e) == 0,
           "a well-formed neighbour message parses");
        ok(e.family == AF_INET, "family is read");
        ok(memcmp(e.addr, &a4, 4) == 0, "destination address is read");
        ok(memcmp(e.mac, mac, 6) == 0, "hardware address is read");
        ok(e.mac_len == 6, "hardware address length is recorded");
        ok(e.state == NUD_REACHABLE, "neighbour state is read");
        ok(e.ifindex == 2, "interface index is read");
    }

    /* a destination-only entry is an entry in progress, never a usable
     * hardware address, so it must be rejected rather than half-installed */
    build_neigh_msg(buf, AF_INET, &a4, 4, mac, NUD_INCOMPLETE, 2, 1, 1);
    ok(neigh_parse((struct nlmsghdr *)buf, &e) != 0,
       "an entry with no hardware address is rejected");

    build_neigh_msg(buf, AF_INET6, &a6, 16, mac, NUD_STALE, 7, 1, 0);
    ok(neigh_parse((struct nlmsghdr *)buf, &e) == 0, "an IPv6 entry parses");
    ok(e.family == AF_INET6 && memcmp(e.addr, &a6, 16) == 0,
       "the 16-byte IPv6 destination is read whole");

    /* states decide whether a hardware address may be installed at all */
    ok(neigh_state_usable(NUD_REACHABLE), "REACHABLE is usable");
    ok(neigh_state_usable(NUD_STALE),
       "STALE is usable: a valid address that is merely unconfirmed");
    ok(neigh_state_usable(NUD_PERMANENT), "PERMANENT is usable");
    ok(!neigh_state_usable(NUD_INCOMPLETE), "INCOMPLETE is not usable");
    ok(!neigh_state_usable(NUD_FAILED),
       "FAILED is not usable: it means the address did not answer");
    ok(!neigh_state_usable(NUD_PROBE), "PROBE is not usable");
    ok(!neigh_state_usable(NUD_NOARP), "NOARP is not usable");
    /* an unrecognised state is evidence that the table is being misread, and
     * is refused rather than treated as usable */
    ok(!neigh_state_usable(0), "an unset state is not usable");
    ok(!neigh_state_usable(0x0100), "an unnamed state is refused, not assumed usable");
    ok(!neigh_state_usable(0xffff), "a combined garbage state is refused");

    /* the state name is what the operator sees in a refusal, so it must not
     * be blank for any state we can be handed */
    ok(strcmp(neigh_state_name(NUD_FAILED), "FAILED") == 0,
       "a failed entry is named FAILED in the diagnostic");
    ok(strcmp(neigh_state_name(NUD_REACHABLE), "REACHABLE") == 0,
       "a reachable entry is named REACHABLE");
}

int main(void) {
    printf("saphira-udpdist unit tests\n");
    t_parser();
    t_hrw();
    t_quic();
    t_frag();
    t_addr();
    t_config();
    t_neigh();
    printf("\n%d checks, %d failure(s)\n", tests, failures);
    return failures ? 1 : 0;
}

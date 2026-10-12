/* saphira-udpdist - L2/L3/L4 frame parsing, fail closed. BUSL-1.1, see LICENSE */
#include "udpdist.h"

#include <string.h>
#include <arpa/inet.h>

#define P_MALFORMED   -1
#define P_TRUNCATED   -2
#define P_NOT_IP      -3
#define P_NOT_UDP     -4
#define P_OVERSIZE    -5
#define P_BAD_CKSUM   -6
#define P_MULTICAST   -7
#define P_BROADCAST   -8

#define ETH_P_IPV4 0x0800
#define ETH_P_IPV6 0x86dd
#define ETH_P_VLAN 0x8100
#define ETH_P_QINQ 0x88a8
#define ETH_P_QINQ2 0x9100

static uint16_t be16(const uint8_t *p) { return (uint16_t)((p[0] << 8) | p[1]); }
static uint32_t be32(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
           ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

static uint32_t sum16(const uint8_t *p, size_t n, uint32_t acc) {
    while (n > 1) {
        acc += be16(p);
        p += 2;
        n -= 2;
    }
    if (n) acc += (uint32_t)p[0] << 8;
    return acc;
}

static uint16_t fold(uint32_t acc) {
    while (acc >> 16) acc = (acc & 0xffff) + (acc >> 16);
    return (uint16_t)(acc & 0xffff);
}

static int udp_cksum_ok(const struct l3info *ip, const uint8_t *udp, size_t udp_len) {
    if (ip->family == AF_INET && be16(udp + 6) == 0) return 1;
    uint8_t pseudo[40];
    size_t alen = (ip->family == AF_INET) ? 4 : 16;
    size_t pn = 0;
    memcpy(pseudo, ip->src.addr, alen);
    pn = alen;
    memcpy(pseudo + pn, ip->dst.addr, alen);
    pn += alen;
    if (ip->family == AF_INET) {
        pseudo[pn++] = 0;
        pseudo[pn++] = IPPROTO_UDP;
        pseudo[pn++] = (uint8_t)(udp_len >> 8);
        pseudo[pn++] = (uint8_t)(udp_len & 0xff);
    } else {
        pseudo[pn++] = (uint8_t)(udp_len >> 24);
        pseudo[pn++] = (uint8_t)(udp_len >> 16);
        pseudo[pn++] = (uint8_t)(udp_len >> 8);
        pseudo[pn++] = (uint8_t)(udp_len);
        pseudo[pn++] = 0;
        pseudo[pn++] = 0;
        pseudo[pn++] = 0;
        pseudo[pn++] = IPPROTO_UDP;
    }
    /* Verification sums the pseudo-header and the datagram with the checksum
     * field left in place. A correct datagram therefore folds to 0xffff. */
    uint32_t acc = sum16(pseudo, pn, 0);
    acc = sum16(udp, udp_len, acc);
    return fold(acc) == 0xffff;
}

static int parse_v4(struct dgram *d, const uint8_t *ip, size_t avail) {
    if (avail < 20) return P_TRUNCATED;
    size_t hlen = (size_t)(ip[0] & 0x0f) * 4;
    if (hlen < 20) return P_MALFORMED;
    if (avail < hlen) return P_TRUNCATED;
    size_t total = be16(ip + 2);
    if (total < hlen) return P_MALFORMED;
    if (total > avail) return P_TRUNCATED;

    d->ip.family = AF_INET;
    d->ip.src.family = AF_INET;
    d->ip.dst.family = AF_INET;
    memcpy(d->ip.src.addr, ip + 12, 4);
    memcpy(d->ip.dst.addr, ip + 16, 4);
    d->ip.proto = ip[9];
    d->ip.l3_off = 0;

    uint16_t fragf = be16(ip + 6);
    uint16_t foff = fragf & 0x1fff;
    int mf = (fragf & 0x2000) ? 1 : 0;
    d->ip.frag_id = be16(ip + 4);
    d->ip.frag = (foff != 0) ? FRAG_SUBSEQUENT : (mf ? FRAG_INITIAL : FRAG_NONE);

    if (d->ip.proto != IPPROTO_UDP) return P_NOT_UDP;
    if (d->ip.frag == FRAG_SUBSEQUENT) {
        d->ip.l4_off = hlen;
        d->ip.l4_len = 0;
        return 0;
    }
    size_t l4len = total - hlen;
    if (l4len < 8) return l4len == 0 ? P_MALFORMED : P_MALFORMED;
    const uint8_t *udp = ip + hlen;
    size_t udplen = be16(udp + 4);
    if (udplen < 8) return P_MALFORMED;
    if (udplen > l4len) return P_MALFORMED;
    d->ip.l4_off = hlen;
    d->ip.l4_len = l4len;
    d->ip.src_port = be16(udp + 0);
    d->ip.dst_port = be16(udp + 2);
    d->ip.payload = udp + 8;
    d->ip.payload_len = udplen - 8;
    return 0;
}

static int parse_v6(struct dgram *d, const uint8_t *ip, size_t avail) {
    if (avail < 40) return P_TRUNCATED;
    size_t plen = be16(ip + 4);
    if (plen == 0) return P_MALFORMED;
    if (40 + plen > avail) return P_TRUNCATED;

    d->ip.family = AF_INET6;
    d->ip.src.family = AF_INET6;
    d->ip.dst.family = AF_INET6;
    memcpy(d->ip.src.addr, ip + 8, 16);
    memcpy(d->ip.dst.addr, ip + 24, 16);
    d->ip.l3_off = 0;
    d->ip.frag = FRAG_NONE;

    uint8_t next = ip[6];
    size_t off = 40;
    int hops = 0;
    for (;;) {
        if (++hops > 8) return P_MALFORMED;
        if (off >= 40 + plen) return P_MALFORMED;
        if (next == IPPROTO_UDP) break;
        if (next == 44) {
            if (off + 8 > 40 + plen) return P_MALFORMED;
            uint16_t fo = be16(ip + off + 2);
            uint32_t fid = be32(ip + off + 4);
            d->ip.frag_id = fid;
            d->ip.frag = (fo & 0xfff8) ? FRAG_SUBSEQUENT
                     : ((fo & 1) ? FRAG_INITIAL : FRAG_NONE);
            next = ip[off];
            off += 8;
            continue;
        }
        if (next == 0 || next == 43 || next == 60 || next == 135) {
            if (off + 2 > 40 + plen) return P_MALFORMED;
            size_t elen = ((size_t)ip[off + 1] + 1) * 8;
            if (off + elen > 40 + plen) return P_MALFORMED;
            next = ip[off];
            off += elen;
            continue;
        }
        if (next == 51) {
            if (off + 2 > 40 + plen) return P_MALFORMED;
            size_t elen = ((size_t)ip[off + 1] + 2) * 4;
            if (off + elen > 40 + plen) return P_MALFORMED;
            next = ip[off];
            off += elen;
            continue;
        }
        /* A well-formed IPv6 packet carrying something other than UDP - ICMPv6,
         * a fragment header we already handled, ESP - is not malformed, it is
         * simply not ours. Conflating the two hides real parse faults. */
        return P_NOT_UDP;
    }
    d->ip.proto = IPPROTO_UDP;

    if (d->ip.frag == FRAG_SUBSEQUENT) {
        d->ip.l4_off = off;
        d->ip.l4_len = 0;
        return 0;
    }
    size_t l4len = (40 + plen) - off;
    if (l4len < 8) return P_MALFORMED;
    const uint8_t *udp = ip + off;
    size_t udplen = be16(udp + 4);
    if (udplen < 8) return P_MALFORMED;
    if (udplen > l4len) return P_MALFORMED;
    d->ip.l4_off = off;
    d->ip.l4_len = l4len;
    d->ip.src_port = be16(udp + 0);
    d->ip.dst_port = be16(udp + 2);
    d->ip.payload = udp + 8;
    d->ip.payload_len = udplen - 8;
    return 0;
}

int frame_parse(const uint8_t *buf, size_t len, uint64_t max_datagram, int csum_ready,
               struct dgram *d) {
    memset(d, 0, sizeof(*d));
    if (len < ETHER_HDR_LEN) return P_TRUNCATED;

    size_t off = ETHER_HDR_LEN;
    uint16_t etype = be16(buf + 12);
    int tags = 0;
    while (etype == ETH_P_VLAN || etype == ETH_P_QINQ || etype == ETH_P_QINQ2) {
        if (++tags > 2) return P_MALFORMED;
        if (off + 4 > len) return P_TRUNCATED;
        etype = be16(buf + off + 2);
        off += 4;
    }
    d->l2_len = off;
    d->frame = buf;
    d->frame_len = len;

    if (etype == ETH_P_IPV4) {
        if (off + 20 > len) return P_TRUNCATED;
        if ((buf[off] >> 4) != 4) return P_MALFORMED;
        int rc = parse_v4(d, buf + off, len - off);
        if (rc != 0) return rc;
    } else if (etype == ETH_P_IPV6) {
        if (off + 40 > len) return P_TRUNCATED;
        if ((buf[off] >> 4) != 6) return P_MALFORMED;
        int rc = parse_v6(d, buf + off, len - off);
        if (rc != 0) return rc;
    } else {
        return P_NOT_IP;
    }

    if (d->ip.frag == FRAG_SUBSEQUENT) return 0;

    if (addr_is_multicast(&d->ip.dst)) return P_MULTICAST;
    if (addr_is_broadcast(&d->ip.dst)) return P_BROADCAST;
    if (d->ip.payload_len + 8 > max_datagram) return P_OVERSIZE;
    /* Only judge the checksum when the kernel says it has finished computing
     * it. A bridge or veth leg hands us a frame whose checksum is still owed
     * by hardware offload, and rejecting those would discard good traffic. */
    if (csum_ready &&
        !udp_cksum_ok(&d->ip, buf + off + d->ip.l4_off, d->ip.payload_len + 8))
        return P_BAD_CKSUM;
    return 0;
}

int checksum_ok(const struct dgram *d) {
    (void)d;
    return 1;
}

int frame_addr_is_frontend(const struct service *svc, const struct uaddr *dst) {
    for (int i = 0; i < svc->nfronts; i++) {
        const struct frontend *f = &svc->fronts[i];
        if (f->addr.family != dst->family) continue;
        size_t alen = (dst->family == AF_INET) ? 4 : 16;
        if (memcmp(f->addr.addr, dst->addr, alen) == 0) return 1;
    }
    return 0;
}

int frame_find_frontend(struct service *svc, const struct l3info *ip) {
    for (int i = 0; i < svc->nfronts; i++) {
        struct frontend *f = &svc->fronts[i];
        if (f->addr.family != ip->dst.family) continue;
        if (f->addr.port != ip->dst_port) continue;
        size_t alen = (ip->dst.family == AF_INET) ? 4 : 16;
        if (memcmp(f->addr.addr, ip->dst.addr, alen) == 0) return i;
    }
    return -1;
}

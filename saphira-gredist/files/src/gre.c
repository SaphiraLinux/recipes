/* Saphira Linux (c) 2026 - MIT Licensed
 * saphira-gredist GRE parsing - derived from Linux gre_demux.c
 */
#include "gredist.h"
#include <string.h>
#include <arpa/inet.h>
#include <netinet/ip.h>
#include <netinet/ip6.h>

uint64_t fnv1a64(const void *data, size_t len, uint64_t seed) {
    const uint8_t *p = (const uint8_t*)data;
    uint64_t h = seed ? seed : 1469598103934665603ULL;
    for (size_t i=0;i<len;i++) {
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

void backend_compute_hash(struct backend *b){
    b->hash = fnv1a64(b->str, strlen(b->str), 0);
    b->hash = splitmix64(b->hash ^ 0x9e3779b97f4a7c15ULL);
}

/* parse outer IP, return family and header len, copy src bytes for HRW */
int parse_outer(const uint8_t *buf, size_t len, int *family, size_t *hdr_len,
                uint8_t *src_bytes, size_t *src_len,
                uint8_t *dst_bytes, size_t *dst_len)
{
    if (len < 1) return -1;
    uint8_t ver = buf[0] >> 4;
    if (ver == 4) {
        if (len < 20) return -1;
        uint8_t ihl = buf[0] & 0x0F;
        size_t hlen = ihl * 4;
        if (hlen < 20) return -1;
        if (len < hlen) return -1;
        uint16_t tot_len = (buf[2]<<8)|buf[3];
        if (tot_len > len) {
            /* packet may be truncated on wire, but check if tot_len claims larger than captured */
            /* still fail if tot_len > len (truncated) */
            return -1;
        }
        if (tot_len < hlen) return -1;
        /* fragmentation check: frag_off field bytes 6-7 */
        uint16_t frag = (buf[6]<<8)|buf[7];
        uint16_t frag_off = frag & 0x1FFF;
        uint8_t mf = (frag & 0x2000) ? 1 : 0;
        if (mf || frag_off != 0) {
            return -2; /* fragment */
        }
        /* protocol must be GRE=47 */
        if (buf[9] != 47) return -1;
        if (family) *family = AF_INET;
        if (hdr_len) *hdr_len = hlen;
        if (src_bytes && src_len) {
            memcpy(src_bytes, buf+12, 4);
            *src_len = 4;
        }
        if (dst_bytes && dst_len) {
            memcpy(dst_bytes, buf+16, 4);
            *dst_len = 4;
        }
        /* oversized check */
        if (tot_len > 9000 && tot_len > len) return -1;
        return 0;
    } else if (ver == 6) {
        if (len < 40) return -1;
        /* check next header = 47 */
        if (buf[6] != 47) return -1;
        uint16_t payload_len = (buf[4]<<8)|buf[5];
        size_t total = 40 + payload_len;
        if (total > len) {
            /* Could be truncated: payload_len claims more than captured */
            return -1;
        }
        /* oversized */
        if (payload_len > 65535 - 40) return -1;
        if (family) *family = AF_INET6;
        if (hdr_len) *hdr_len = 40;
        if (src_bytes && src_len) {
            memcpy(src_bytes, buf+8, 16);
            *src_len = 16;
        }
        if (dst_bytes && dst_len) {
            memcpy(dst_bytes, buf+24, 16);
            *dst_len = 16;
        }
        return 0;
    } else {
        return -1;
    }
}

/* GRE parse - mimics gre_parse_header from Linux
 * outer_hdr_len = ip header length
 * buf/len = full packet including outer IP
 */
int gre_parse(const uint8_t *buf, size_t len, size_t outer_hdr_len, struct gre_info *out)
{
    memset(out,0,sizeof(*out));
    if (len < outer_hdr_len + 4) return -1;
    const uint8_t *g = buf + outer_hdr_len;
    size_t remain = len - outer_hdr_len;
    if (remain < 4) return -1;
    uint16_t flags = (g[0]<<8)|g[1];
    uint16_t proto = (g[2]<<8)|g[3];
    out->flags = flags;
    out->proto = htons(proto); /* store net order similar to kernel? but we keep host for checks */
    /* Linux checks: if flags & (GRE_VERSION|GRE_ROUTING) => EINVAL */
    if (flags & GRE_F_VERSION) return -2; /* version error -> fail closed */
    if (flags & GRE_F_ROUTING) return -2;
    if (flags & 0x00F8) { /* reserved bits per RFC? linux's GRE_FLAGS mask 0x0078, but also checks 0x00F8? we treat unknown flags as error? */
        /* Keep permissive: only fail on ROUTING/VERSION, others allowed but must validate lengths */
    }
    int hdr_len = 4;
    if (flags & GRE_F_CSUM) hdr_len += 4;
    if (flags & GRE_F_KEY) hdr_len += 4;
    if (flags & GRE_F_SEQ) hdr_len += 4;
    if (flags & GRE_F_ACK) hdr_len += 4; /* not standard but handle */
    /* Also handle WCCP extra? ignore */
    if ((int)remain < hdr_len) return -1; /* truncated claims bytes absent */
    out->has_csum = (flags & GRE_F_CSUM) ? 1 : 0;
    out->has_key = (flags & GRE_F_KEY) ? 1 : 0;
    out->has_seq = (flags & GRE_F_SEQ) ? 1 : 0;
    out->hdr_len = hdr_len;
    /* extract key if present: order is CSUM, KEY, SEQ (ACK after?) */
    size_t off = 4;
    if (flags & GRE_F_CSUM) {
        /* checksum 2 bytes + reserved 2 */
        off += 4;
    }
    if (flags & GRE_F_KEY) {
        if (off+4 > remain) return -1;
        out->key = (g[off]<<24)|(g[off+1]<<16)|(g[off+2]<<8)|g[off+3];
        off += 4;
    }
    if (flags & GRE_F_SEQ) {
        if (off+4 > remain) return -1;
        out->seq = (g[off]<<24)|(g[off+1]<<16)|(g[off+2]<<8)|g[off+3];
        off += 4;
    }
    /* payload proto validation? allow any */
    (void)proto;
    return 0;
}

int select_backend(struct service *svc, const uint8_t *src_bytes, size_t src_len, const struct gre_info *gre)
{
    if (svc->nbackends==0) return -1;
    /* Build flow key: src_bytes + optional key */
    uint8_t flow_buf[32];
    size_t flow_len=0;
    if (src_len>0 && src_len<=16) {
        memcpy(flow_buf, src_bytes, src_len);
        flow_len = src_len;
    }
    if (gre && gre->has_key) {
        if (flow_len+4 <= sizeof(flow_buf)) {
            flow_buf[flow_len++] = (gre->key>>24)&0xFF;
            flow_buf[flow_len++] = (gre->key>>16)&0xFF;
            flow_buf[flow_len++] = (gre->key>>8)&0xFF;
            flow_buf[flow_len++] = gre->key & 0xFF;
        }
    }
    uint64_t flow_hash = fnv1a64(flow_buf, flow_len, 1469598103934665603ULL);
    flow_hash = splitmix64(flow_hash);

    int best = -1;
    uint64_t best_score = 0;
    for (int i=0;i<svc->nbackends;i++) {
        struct backend *b = &svc->backends[i];
        if (!b->healthy) continue;
        uint64_t h = b->hash ^ flow_hash;
        h = splitmix64(h + 0x9e3779b97f4a7c15ULL + (uint64_t)i*0xbf58476d1ce4e5b9ULL);
        /* weight could incorporate backend index? keep simple */
        if (best==-1 || h > best_score) {
            best_score = h;
            best = i;
        }
    }
    /* if all unhealthy, fallback to any (fail closed? we drop). Return -1 to indicate no healthy */
    if (best==-1) return -1;
    return best;
}

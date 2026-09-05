/* Saphira Linux (c) 2026 - MIT Licensed
 * saphira-gredist - Protocol 47/GRE distributor
 * Reference: Linux net/ipv4/gre_demux.c and net/ipv6/ip6_gre.c
 *            net/gre.h, linux/if_tunnel.h
 */
#ifndef GREDIST_H
#define GREDIST_H

#include <stdint.h>
#include <stddef.h>
#include <netinet/in.h>
#include <sys/socket.h>

#define MAX_BACKENDS 64
#define MAX_FRONTENDS 4
#define BUF_SIZE 65536
#define HEALTH_INTERVAL_SEC 2
#define HEALTH_FAIL_THRESHOLD 2
#define HEALTH_OK_THRESHOLD 2

/* GRE flags in wire (network) order same as linux/if_tunnel.h */
#define GRE_F_CSUM    0x8000
#define GRE_F_ROUTING 0x4000
#define GRE_F_KEY     0x2000
#define GRE_F_SEQ     0x1000
#define GRE_F_STRICT  0x0800
#define GRE_F_REC     0x0700
#define GRE_F_ACK     0x0080
#define GRE_F_VERSION 0x0007

struct gre_info {
    uint16_t flags;   /* host order */
    uint16_t proto;   /* network order */
    uint32_t key;
    int has_key;
    uint32_t seq;
    int has_seq;
    int has_csum;
    int hdr_len;
};

struct backend {
    char str[128];
    int family; /* AF_INET / AF_INET6 */
    struct sockaddr_storage ss;
    socklen_t ss_len;
    uint64_t hash; /* hash of str for HRW */
    int healthy;
    int fail_cnt;
    int ok_cnt;
    uint64_t pkts;
    uint64_t bytes;
    time_t last_probe;
};

struct service {
    char name[128];
    char frontend_str[128];
    int frontend_family;
    struct sockaddr_storage frontend_ss;
    socklen_t frontend_len;
    struct backend backends[MAX_BACKENDS];
    int nbackends;
    /* stats */
    uint64_t rx;
    uint64_t forwarded;
    uint64_t dropped_malformed;
    uint64_t dropped_truncated;
    uint64_t dropped_oversized;
    uint64_t dropped_no_backend;
    uint64_t dropped_queue;
    uint64_t dropped_frag;
    uint64_t dropped_version;
};

uint64_t fnv1a64(const void *data, size_t len, uint64_t seed);
uint64_t splitmix64(uint64_t x);
int gre_parse(const uint8_t *buf, size_t len, size_t outer_hdr_len, struct gre_info *out);
int parse_outer(const uint8_t *buf, size_t len, int *family, size_t *hdr_len,
                uint8_t *src_bytes, size_t *src_len,
                uint8_t *dst_bytes, size_t *dst_len);
int select_backend(struct service *svc, const uint8_t *src_bytes, size_t src_len, const struct gre_info *gre);
void backend_compute_hash(struct backend *b);
int load_config(const char *path, struct service *svc, const char *service_name);

#endif

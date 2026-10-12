/* saphira-udpdist - L4 UDP distributor, DSR/LVS-DR style. BUSL-1.1, see LICENSE */
#ifndef UDPDIST_H
#define UDPDIST_H

#include <stdint.h>
#include <stddef.h>
#include <time.h>
#include <netinet/in.h>
#include <sys/socket.h>

#define UD_MAX_BACKENDS 64
#define UD_MAX_FRONTS 32
#define UD_MAX_IFACES 8
#define UD_MAX_QUIC_CFG 8
#define UD_NAME_MAX 64
#define UD_ID_MAX 128
#define UD_IFNAME_MAX 32
#define UD_LINE_MAX 1024

#define FRAG_TABLE_SLOTS 4096
#define QUIC_FALLBACK_SLOTS 4096

#define HEALTH_INTERVAL_SEC 2
#define HEALTH_FAIL_THRESHOLD 2
#define HEALTH_OK_THRESHOLD 2
#define PROBE_TIMEOUT_SEC 2

#define FRAG_ASSOC_TTL_MS 4000
#define QUIC_FALLBACK_TTL_MS 8000

#define MAX_DATAGRAM_DEFAULT 9000
#define ETHER_HDR_LEN 14

enum {
    FRONT_PROTO_UDP = 0,
    FRONT_PROTO_QUIC = 1
};

enum {
    QUIC_MODE_FALLBACK = 0,
    QUIC_MODE_QUIC_LB = 1
};

enum {
    FRAG_NONE = 0,
    FRAG_INITIAL,
    FRAG_SUBSEQUENT
};

struct uaddr {
    int family;
    uint8_t addr[16];
    uint16_t port;
    uint32_t scope_id;
};

struct quic_cfg {
    int in_use;
    int config_id;
    int cid_len;
    int self_describing;
    int server_id_len;
};

struct backend {
    char id[UD_ID_MAX];
    struct uaddr addr;
    uint8_t mac[6];
    int mac_configured;
    int mac_learned;
    uint32_t ifindex_hint;
    uint64_t hash;
    int healthy;
    int fail_cnt;
    int ok_cnt;
    time_t last_probe;
    uint64_t quic_sid;
    int quic_sid_set;
    uint64_t pkts;
    uint64_t bytes;
};

struct frontend {
    char id[UD_ID_MAX];
    struct uaddr addr;
    int iface;              /* index into svc->ifaces */
    int sink_fd;
    int proto;
    int quic_mode;
    uint64_t rx;
    uint64_t frag_rx;
    uint64_t quic_routable;
    uint64_t quic_fallback_hit;
    uint64_t quic_fallback_miss;
    uint64_t quic_unroutable;
    uint64_t quic_backend_unknown;
    uint64_t quic_backend_down;
    uint64_t no_backend;
    uint64_t not_ours;
    uint64_t self_echo;
    uint64_t sink_observed;
};

struct iface {
    char name[UD_IFNAME_MAX];
    int index;
    int rx_fd;
    int tx_fd;
    uint8_t mac[6];
    int in_use;
};

struct frag_assoc {
    int used;
    uint64_t key;
    struct uaddr src;
    struct uaddr dst;
    uint32_t frag_id;
    uint8_t proto;
    int front;
    int backend;
    uint64_t expiry_ms;
};

struct quic_fb {
    int used;
    uint64_t key;
    struct uaddr client;
    struct uaddr front;
    int backend;
    uint64_t expiry_ms;
};

struct stats {
    uint64_t rx;
    uint64_t forwarded;
    uint64_t non_ip;
    uint64_t not_udp;
    uint64_t malformed;
    uint64_t truncated;
    uint64_t oversized;
    uint64_t bad_checksum;
    uint64_t multicast;
    uint64_t broadcast;
    uint64_t frag_initial;
    uint64_t frag_subsequent;
    uint64_t orphan_fragment;
    uint64_t fragment_table_full;
    uint64_t frag_conflict;
    uint64_t no_backend;
    uint64_t send_failed;
    uint64_t not_ours;
    uint64_t self_echo;
    uint64_t quic_routable;
    uint64_t quic_fallback_hit;
    uint64_t quic_fallback_miss;
    uint64_t quic_unroutable;
    uint64_t quic_backend_unknown;
    uint64_t quic_backend_down;
    uint64_t mac_changed;
    uint64_t mac_unresolved;
    uint64_t mac_learned;
};

struct service {
    char name[UD_NAME_MAX];
    char config_path[512];
    struct iface ifaces[UD_MAX_IFACES];
    int nifaces;
    struct frontend fronts[UD_MAX_FRONTS];
    int nfronts;
    struct backend backs[UD_MAX_BACKENDS];
    int nbacks;
    struct quic_cfg quic[UD_MAX_QUIC_CFG];
    int nquic;
    uint64_t max_datagram;
    int require_mac;
    int skip_csum_check;
    int skip_health_check;
    int validate_only;
    struct stats st;
};

struct l3info {
    int family;
    struct uaddr src;
    struct uaddr dst;
    uint8_t proto;
    size_t l3_off;
    size_t l4_off;
    size_t l4_len;
    int frag;
    uint32_t frag_id;
    uint16_t src_port;
    uint16_t dst_port;
    const uint8_t *payload;
    size_t payload_len;
};

struct dgram {
    struct l3info ip;
    size_t l2_len;
    const uint8_t *frame;
    size_t frame_len;
};

uint64_t fnv1a64(const void *data, size_t len, uint64_t seed);
uint64_t splitmix64(uint64_t x);
uint64_t now_ms(void);

int addr_parse(const char *s, struct uaddr *out);
int addr_parse_hostport(const char *s, struct uaddr *out);
void addr_format(const struct uaddr *a, char *buf, size_t len);
void addr_id(const struct uaddr *a, char *buf, size_t len);
void addr_normalize(struct uaddr *a);
int addr_is_multicast(const struct uaddr *a);
int addr_is_broadcast(const struct uaddr *a);
int mac_parse(const char *s, uint8_t out[6]);
void mac_format(const uint8_t mac[6], char *buf, size_t len);

int backend_compute_hash(struct backend *b);
int hrw_select(struct service *svc, const struct uaddr *client,
               uint16_t sport, const struct uaddr *front, uint16_t dport);

int frag_lookup(struct service *svc, const struct l3info *ip);
int frag_insert(struct service *svc, const struct l3info *ip, int backend);
void frag_expire(struct service *svc, uint64_t now);

int quic_configure(struct service *svc, const struct quic_cfg *cfg);
const struct quic_cfg *quic_find_cfg(const struct service *svc, int config_id);
int backend_by_sid(const struct service *svc, uint64_t sid);
void quic_classify(const uint8_t *payload, size_t len, struct service *svc,
                   int *is_quic, int *routable, uint64_t *server_id);
int quic_select(struct service *svc, struct frontend *f, const struct l3info *ip,
                int *state);
#define QUIC_STATE_UDP 0
#define QUIC_STATE_LB 1
#define QUIC_STATE_FB 2
void quic_fb_expire(struct service *svc, uint64_t now);

int frame_parse(const uint8_t *buf, size_t len, uint64_t max_datagram, int csum_ready,
               struct dgram *d);
int checksum_ok(const struct dgram *d);
int frame_find_frontend(struct service *svc, const struct l3info *ip);
int frame_addr_is_frontend(const struct service *svc, const struct uaddr *dst);

int config_load(const char *path, struct service *svc, const char *name);
int iface_index(struct service *svc, const char *name);
int name_is_valid(const char *s);

int health_open(struct service *svc);
int health_selftest(struct service *svc);
int probe_send(struct service *svc, int i);
int health_fds(int fds[2]);
void health_tick(struct service *svc);
int health_recv(struct service *svc, int fd);
void health_timeout(struct service *svc);
void health_close(void);
int validate_backends(struct service *svc);

/* neighbour discovery: ask the kernel, never speak ARP ourselves */
struct nlmsghdr;
#define NEIGH_MAX 256
struct neigh_entry {
    int family;
    uint8_t addr[16];
    uint8_t mac[6];
    int mac_len;
    uint32_t ifindex;
    uint16_t state;
};
int neigh_parse(const struct nlmsghdr *nlh, struct neigh_entry *e);
int neigh_get(const struct uaddr *a, uint32_t ifindex, uint8_t mac[6], uint16_t *state);
int neighbour_resolve(const struct uaddr *a, uint32_t ifindex, int tries, int delay_ms);
int neigh_state_usable(uint16_t s);
const char *neigh_state_name(uint16_t s);
int neigh_watch_open(void);
int neigh_watch_open_once(void);
int neigh_watch_drain(struct neigh_entry *out, int max, int *ndeleted);
void neigh_close(void);

#endif

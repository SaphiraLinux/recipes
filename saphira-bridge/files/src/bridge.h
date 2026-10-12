/*
 * saphira-bridge - a tiny userspace Ethernet MAC-learning bridge.
 * BUSL-1.1, see LICENSE.
 *
 * Linux owns ARP, NDP, IP, routing and NAT. This moves Ethernet frames
 * between ports and does nothing else. See README for the boundaries.
 */
#ifndef SAPHIRA_BRIDGE_H
#define SAPHIRA_BRIDGE_H

#include <stdint.h>
#include <stddef.h>
#include <time.h>
#include <stdio.h>

#define BR_MAX_PORTS 32
/* IFNAMSIZ, inclusive of the terminator: a longer name cannot be
 * represented in the kernel interface structure at all. */
#define BR_IFNAME_MAX 16
#define BR_PORT_MAX 16
#define BR_CAM_MAX 65536
#define BR_CAM_MIN 8
#define BR_RX_BUFSZ 2048
#define BR_MACLEN 6
#define BR_ETHERTYPE_LEN 2
#define BR_ETH_HDR_LEN 14

/* An action is one decision, fully resolved, with no policy left inside the
 * forwarding path: send it out exactly this port, send it out every port but
 * one, or drop it. */
enum br_action {
    BR_DROP = 0,   /* never reaches the wire; a reason is always recorded */
    BR_UNICAST,    /* to exactly one port */
    BR_FLOOD       /* to every port except the one it arrived on */
};

/* Why a frame was dropped. Kept distinct from the counters so a log line and a
 * statistic cannot disagree about the reason. */
enum br_reason {
    BR_R_NONE = 0,
    BR_R_TOO_SHORT,
    BR_R_VLAN_TAGGED,
    BR_R_RESERVED,
    BR_R_TX_FAILED,
    BR_R_NO_EGRESS
};

struct br_port {
    char name[BR_IFNAME_MAX];
    int index;
    int fd;        /* receive, in the poll set */
    int tx_fd;     /* transmit, a separate descriptor */
    int vnet_rx;   /* rx socket takes a virtio_net_hdr */
    int vnet_tx;   /* tx socket accepts a virtio_net_hdr */
    int vnet_rx_ok;
    int ifindex;
    int ignore_outgoing;      /* kernel-side suppression actually enabled */
    int want_ignore_outgoing; /* what the configuration asked for */
    uint8_t hwaddr[BR_MACLEN];
    uint64_t rx;
    uint64_t tx;
    uint64_t tx_failed;
    uint64_t dropped;   /* frames this port could not even offer onward */
};

struct br_cam_entry {
    uint8_t mac[BR_MACLEN];
    int port;            /* -1 when the slot is free */
    int used;
    time_t last_seen;
    uint32_t next;       /* bucket chain, BR_CAM_END terminates */
};

struct br_cam {
    struct br_cam_entry *ents;
    uint32_t *buckets;
    uint32_t nbuckets;
    int max_entries;
    int age_secs;
    uint64_t learnt;
    uint64_t moved;        /* a MAC reappeared on a different port: loop smell */
    uint64_t evicted;      /* table was full, least-recently-seen went */
    uint64_t expired;      /* swept out after idle age */
};

struct br_stats {
    uint64_t rx;
    uint64_t forwarded;
    uint64_t flooded;
    uint64_t unicast;
    uint64_t dropped;
    uint64_t too_short;
    uint64_t vlan_tagged;
    uint64_t reserved;
    uint64_t source_not_learned;  /* learning refused: group-address source */
    uint64_t tx_failed;
    uint64_t no_egress;
    /* Direction is decided by sll_pkttype, never by the auxdata status bit.
     * Both are counted so the two mechanisms can be compared and the reason a
     * frame was discarded is always attributable to one of them. */
    uint64_t self_echo;        /* rejected: sll_pkttype said PACKET_OUTGOING */
    uint64_t auxdata_outgoing; /* auxdata said outgoing, but sll_pkttype did not */
    uint64_t pkttype_host;
    uint64_t pkttype_broadcast;
    uint64_t pkttype_multicast;
    uint64_t pkttype_otherhost;
    uint64_t pkttype_outgoing;
    uint64_t pkttype_unknown;
    /* Checksum and VLAN state as the kernel reported it on ingress. */
    uint64_t aux_csumnotready;
    uint64_t aux_csum_valid;
    uint64_t aux_vlan_valid;
    uint64_t aux_vlan_tpid_valid;
    /* Deferred-checksum state, preserved rather than computed. */
    uint64_t deferred_in;        /* arrived with VIRTIO_NET_HDR_F_NEEDS_CSUM */
    uint64_t deferred_carried;   /* handed on with the metadata intact */
    uint64_t deferred_refused;   /* arrived incomplete and could not be carried */
    uint64_t csumnotready_seen;  /* auxdata said incomplete */
    int vnet_hdr;                /* PACKET_VNET_HDR accepted on rx and tx */
    int64_t ignore_outgoing_effective;  /* 0/1 whether the kernel option is on */
};

struct br_config {
    char svcname[64];
    struct br_port ports[BR_MAX_PORTS];
    int nports;
    int age_secs;
    int max_entries;
    int promiscuous;
    int ignore_outgoing;   /* kernel-side suppression, where supported */
    int sample;            /* log every Nth frame with its addresses, 0 = off */
    int drop_user;
    int drop_group;
    int validate_only;
};

/* Kernel-reported facts about a received frame that are not visible in the
 * delivered bytes. Both matter: a frame can arrive with the transport checksum
 * still uncomputed, and a tag can be stripped from the buffer while the kernel
 * still reports the tag. A bridge that only reads bytes cannot see either. */
struct br_meta {
    int vlan_valid;      /* TP_STATUS_VLAN_VALID: a tag was removed from the bytes */
    int vlan_tpid_valid;
    unsigned vlan_tci;
    unsigned vlan_tpid;
    int csumnotready;    /* TP_STATUS_CSUMNOTREADY: checksum not yet computed */
    int csum_valid;      /* TP_STATUS_CSUM_VALID */
};

struct br_decision {
    enum br_action action;
    int port;              /* BR_UNICAST only */
    enum br_reason reason; /* BR_DROP only */
    int learned;           /* source address was learnt from this frame */
    int moved;             /* learning observed a port change */
    int evicted;           /* learning had to evict to make room */
    int not_learned;       /* the source address was refused for learning */
};

/* cam.c */
int br_cam_init(struct br_cam *c, int max_entries, int age_secs);
void br_cam_free(struct br_cam *c);
int br_cam_lookup(const struct br_cam *c, const uint8_t mac[BR_MACLEN], int *port);
int br_cam_learn(struct br_cam *c, const uint8_t mac[BR_MACLEN], int port,
                 time_t now, int *moved, int *evicted);
int br_cam_age(struct br_cam *c, time_t now);
int br_cam_count(const struct br_cam *c);
int br_cam_count_evictable(const struct br_cam *c);
uint32_t br_mac_hash(const uint8_t mac[BR_MACLEN]);

/* eth.c */
int br_mac_parse(const char *s, uint8_t out[BR_MACLEN]);
void br_mac_format(const uint8_t mac[BR_MACLEN], char *buf, size_t len);
int br_is_broadcast(const uint8_t mac[BR_MACLEN]);
int br_is_multicast(const uint8_t mac[BR_MACLEN]);
int br_is_reserved(const uint8_t mac[BR_MACLEN]);
int br_is_vlan_tagged(const uint8_t *frame, size_t len);
unsigned br_ethertype(const uint8_t *frame, size_t len);
void br_ethertype_format(unsigned type, char *buf, size_t len);

/* fwd.c */
int br_fwd_decide(const uint8_t *frame, size_t len, int in_port, int nports,
                  struct br_cam *cam, time_t now, const struct br_meta *meta,
                  struct br_decision *d);
int br_meta_has_vlan(const struct br_meta *m);
const char *br_reason_name(enum br_reason r);
const char *br_action_name(enum br_action a);

/* config.c */
int br_config_load(const char *path, struct br_config *cfg, const char *name);
int br_name_is_valid(const char *s);
void br_log_msg(const char *fmt, ...);
void br_log_err(const char *fmt, ...);

/* bridge.c */
int br_open_port(struct br_port *p);
int br_close_port(struct br_port *p);
struct virtio_net_hdr;
int br_send_frame(struct br_port *p, const uint8_t *frame, size_t len,
                  const struct virtio_net_hdr *vh);
void br_count_reason(struct br_stats *st, enum br_reason r);

#endif

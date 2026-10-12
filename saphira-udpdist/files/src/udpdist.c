/* saphira-udpdist - L4 UDP distributor, DSR/LVS-DR style. BUSL-1.1, see LICENSE */
#ifndef _DEFAULT_SOURCE
#define _DEFAULT_SOURCE
#endif
#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include "udpdist.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <poll.h>
#include <stdarg.h>
#include <ctype.h>
#include <pwd.h>
#include <grp.h>
#include <syslog.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <sys/timerfd.h>
#include <net/if.h>
#include <ifaddrs.h>
#include <netpacket/packet.h>
#include <net/ethernet.h>
#include <arpa/inet.h>

/* From <linux/if_packet.h>. Declared here because including that header
 * alongside <netpacket/packet.h> redefines struct sockaddr_ll. */
struct tpacket_auxdata_local {
    uint32_t tp_status;
    uint32_t tp_len;
    uint32_t tp_snaplen;
    uint16_t tp_mac;
    uint16_t tp_net;
    uint16_t tp_vlan_tci;
    uint16_t tp_vlan_tpid;
};
#define TP_STATUS_CSUMNOTREADY_LOCAL 0x00000008
/* PACKET_OUTGOING / TP_STATUS_OUTGOING: this frame left this host through this
 * socket. Without this filter the distributor would receive its own
 * re-emitted frames and forward them again, for ever. */
#define TP_STATUS_OUTGOING_LOCAL 0x00000004
#define TP_AUXDATA_LEN ((int)sizeof(struct tpacket_auxdata_local))

#define PROG "udpdist"
#define UDPDIST_USER "udpdist"
#define UDPDIST_GROUP "udpdist"
#define RXBUF 65536

static int opt_syslog;
static volatile sig_atomic_t do_quit, do_reload, do_dump;

static void vlog(const char *fmt, va_list ap) {
    if (opt_syslog) vsyslog(LOG_INFO, fmt, ap);
    else { vfprintf(stderr, fmt, ap); fputc('\n', stderr); }
}
static void log_msg(const char *fmt, ...) {
    va_list ap; va_start(ap, fmt); vlog(fmt, ap); va_end(ap);
}
static void log_err(const char *fmt, ...) {
    if (opt_syslog) {
        va_list ap; va_start(ap, fmt); vsyslog(LOG_ERR, fmt, ap); va_end(ap);
    } else {
        va_list ap; va_start(ap, fmt);
        fprintf(stderr, "%s: ", PROG);
        vfprintf(stderr, fmt, ap);
        fputc('\n', stderr);
        va_end(ap);
    }
}

static void sig_handler(int sig) {
    if (sig == SIGINT || sig == SIGTERM) do_quit = 1;
    else if (sig == SIGHUP) do_reload = 1;
    else if (sig == SIGUSR1) do_dump = 1;
}

static int set_nonblock(int fd) {
    int fl = fcntl(fd, F_GETFL, 0);
    if (fl == -1) return -1;
    return fcntl(fd, F_SETFL, fl | O_NONBLOCK);
}

static int if_mac(const char *name, uint8_t out[6]) {
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0) return -1;
    struct ifreq ifr;
    memset(&ifr, 0, sizeof(ifr));
    snprintf(ifr.ifr_name, IFNAMSIZ, "%s", name);
    int rc = -1;
    if (ioctl(fd, SIOCGIFHWADDR, &ifr) == 0) {
        memcpy(out, ifr.ifr_hwaddr.sa_data, 6);
        rc = 0;
    }
    close(fd);
    return rc;
}

static int open_packet_socket(int ifindex) {
    int fd = socket(AF_PACKET, SOCK_RAW, htons(ETH_P_ALL));
    if (fd < 0) return -1;
    struct sockaddr_ll sll;
    memset(&sll, 0, sizeof(sll));
    sll.sll_family = AF_PACKET;
    sll.sll_protocol = htons(ETH_P_ALL);
    sll.sll_ifindex = ifindex;
    if (bind(fd, (struct sockaddr *)&sll, sizeof(sll)) != 0) {
        close(fd);
        return -1;
    }
    /* Ask for the auxiliary data so we can tell whether the kernel has finished
     * the transport checksum, rather than guessing from a mismatch. */
    int one = 1;
    if (setsockopt(fd, SOL_PACKET, PACKET_AUXDATA, &one, sizeof(one)) != 0) {
        log_err("PACKET_AUXDATA: %s", strerror(errno));
        close(fd);
        return -1;
    }
    set_nonblock(fd);
    return fd;
}

static void close_ifaces(struct service *svc) {
    for (int i = 0; i < svc->nifaces; i++) {
        if (svc->ifaces[i].rx_fd >= 0) close(svc->ifaces[i].rx_fd);
        if (svc->ifaces[i].tx_fd >= 0) close(svc->ifaces[i].tx_fd);
        svc->ifaces[i].rx_fd = svc->ifaces[i].tx_fd = -1;
    }
}

static void close_sinks(struct service *svc) {
    for (int i = 0; i < svc->nfronts; i++) {
        if (svc->fronts[i].sink_fd >= 0) close(svc->fronts[i].sink_fd);
        svc->fronts[i].sink_fd = -1;
    }
}

static int resolve_iface_for(struct service *svc, struct uaddr *a) {
    struct ifaddrs *ifa, *p;
    if (getifaddrs(&ifa) != 0) return -1;
    int found = -1;
    for (p = ifa; p && found < 0; p = p->ifa_next) {
        if (!p->ifa_addr) continue;
        if (p->ifa_addr->sa_family != a->family) continue;
        size_t alen = (a->family == AF_INET) ? 4 : 16;
        const void *ra = (a->family == AF_INET)
            ? (const void *)&((struct sockaddr_in *)p->ifa_addr)->sin_addr
            : (const void *)&((struct sockaddr_in6 *)p->ifa_addr)->sin6_addr;
        if (memcmp(ra, a->addr, alen) == 0) {
            int idx = iface_index(svc, p->ifa_name);
            if (idx >= 0) found = idx;
        }
    }
    freeifaddrs(ifa);
    return found;
}

/* Checksum offload must be off on any interface this daemon redirects on.
 * The kernel hands us a frame whose transport checksum is still owed by
 * hardware, and we forward those bytes verbatim; the backend then discards the
 * datagram at its own checksum verification, so every packet is lost with a
 * successful send and a healthy-looking forward counter. Detecting this from
 * the counters is far too late, so it is checked before the first packet. */
static int csum_offload_is_on(const char *ifname, char *what, size_t whatlen) {
    char path[256];
    snprintf(path, sizeof(path), "/sys/class/net/%s/features", ifname);
    FILE *f = fopen(path, "r");
    if (!f) return -1;
    char line[4096];
    size_t n = fread(line, 1, sizeof(line) - 1, f);
    fclose(f);
    line[n] = '\0';
    if (strstr(line, "tx-checksum-ip-generic") || strstr(line, "tx-checksumming")) {
        snprintf(what, whatlen, "tx");
        return 1;
    }
    if (strstr(line, "rx-checksumming")) {
        snprintf(what, whatlen, "rx");
        return 1;
    }
    return 0;
}

static int prepare(struct service *svc) {
    for (int i = 0; i < svc->nfronts; i++) {
        if (svc->fronts[i].iface >= 0) continue;
        int idx = resolve_iface_for(svc, &svc->fronts[i].addr);
        if (idx < 0) {
            log_err("cannot determine which interface owns the frontend address %s; "
                    "set iface=NAME on the frontend", svc->fronts[i].id);
            return -1;
        }
        svc->fronts[i].iface = idx;
    }
    for (int i = 0; i < svc->nifaces; i++) {
        svc->ifaces[i].index = if_nametoindex(svc->ifaces[i].name);
        if (svc->ifaces[i].index == 0) {
            log_err("interface '%s' does not exist", svc->ifaces[i].name);
            return -1;
        }
        if (if_mac(svc->ifaces[i].name, svc->ifaces[i].mac) != 0) {
            log_err("cannot read the hardware address of '%s'", svc->ifaces[i].name);
            return -1;
        }
    }
    for (int i = 0; i < svc->nfronts; i++) {
        struct frontend *f = &svc->fronts[i];
        if (f->iface < 0 || f->iface >= svc->nifaces) {
            log_err("frontend %s references an unknown interface", f->id);
            return -1;
        }
        int ifi = svc->ifaces[f->iface].index;
        f->sink_fd = socket(f->addr.family, SOCK_DGRAM, IPPROTO_UDP);
        if (f->sink_fd < 0) {
            log_err("sink socket for %s: %s", f->id, strerror(errno));
            return -1;
        }
        if (f->addr.family == AF_INET6 && f->addr.scope_id)
            setsockopt(f->sink_fd, IPPROTO_IPV6, IPV6_V6ONLY, &(int){1}, sizeof(int));
        int rc = bind(f->sink_fd, (struct sockaddr *)&f->addr,
                      f->addr.family == AF_INET ? sizeof(struct sockaddr_in)
                                               : sizeof(struct sockaddr_in6));
        if (rc != 0) {
            log_err("cannot bind the sink socket for %s: %s. The VIP must be "
                    "configured on this host; udpdist binds it only to stop the "
                    "kernel emitting ICMP port-unreachable for datagrams it is "
                    "forwarding by other means.", f->id, strerror(errno));
            close(f->sink_fd);
            f->sink_fd = -1;
            return -1;
        }
        set_nonblock(f->sink_fd);
        (void)ifi;
    }
    for (int i = 0; i < svc->nifaces; i++) {
        svc->ifaces[i].rx_fd = open_packet_socket(svc->ifaces[i].index);
        if (svc->ifaces[i].rx_fd < 0) {
            log_err("AF_PACKET receive socket on '%s': %s (CAP_NET_RAW required)",
                    svc->ifaces[i].name, strerror(errno));
            return -1;
        }
        svc->ifaces[i].tx_fd = open_packet_socket(svc->ifaces[i].index);
        if (svc->ifaces[i].tx_fd < 0) {
            log_err("AF_PACKET send socket on '%s': %s", svc->ifaces[i].name,
                    strerror(errno));
            return -1;
        }
    }
    return 0;
}

static int drop_privileges(void) {
    if (geteuid() != 0) {
        log_msg("running unprivileged as uid %d; no drop required", (int)geteuid());
        return 0;
    }
    struct passwd *pw = getpwnam(UDPDIST_USER);
    if (!pw) {
        log_err("service account '%s' does not exist; cannot drop privileges",
                UDPDIST_USER);
        return -1;
    }
    if (getgrnam(UDPDIST_GROUP) == NULL) {
        log_err("service group '%s' does not exist", UDPDIST_GROUP);
        return -1;
    }
    gid_t gid = pw->pw_gid;
    /* A user namespace can forbid setgroups(2) outright. Ignoring that is only
     * safe when there is nothing to drop, so check rather than assume. */
    if (setgroups(1, &gid) != 0) {
        if (errno != EPERM) {
            log_err("setgroups: %s", strerror(errno));
            return -1;
        }
        int have = getgroups(0, NULL);
        if (have > 1) {
            log_err("setgroups is not permitted and %d supplementary groups would "
                    "remain; refusing to continue", have);
            return -1;
        }
        log_msg("setgroups is not permitted here and there are no supplementary "
                "groups to drop; continuing");
    }
    if (setgid(gid) != 0) { log_err("setgid: %s", strerror(errno)); return -1; }
    if (setuid(pw->pw_uid) != 0) { log_err("setuid: %s", strerror(errno)); return -1; }
    if (setuid(0) == 0 || geteuid() == 0 || getuid() == 0) {
        log_err("privilege drop did not take effect");
        return -1;
    }
    log_msg("dropped privileges: uid=%d gid=%d; no capability is retained",
            (int)getuid(), (int)getgid());
    return 0;
}

static int neigh_lookup(const struct uaddr *a, uint8_t mac[6]) {
    const char *path;
    if (a->family == AF_INET) path = "/proc/net/arp";
    else {
        path = "/proc/net/ipv6_neigh";
        if (access(path, R_OK) != 0) return -2;
    }
    FILE *f = fopen(path, "r");
    if (!f) return (a->family == AF_INET) ? -1 : -2;

    char line[512];
    int found = -1;
    char tok[16][64];
    while (fgets(line, sizeof(line), f)) {
        int n = 0;
        char *save = line;
        for (char *p = strtok_r(save, " \t\n", &save); p && n < 16;
             p = strtok_r(NULL, " \t\n", &save))
            snprintf(tok[n++], sizeof(tok[0]), "%s", p);
        if (n < 2) continue;
        if (a->family == AF_INET) {
            if (n < 4) continue;
            struct in_addr t;
            if (inet_pton(AF_INET, tok[0], &t) != 1) continue;
            if (memcmp(&t, a->addr, 4) != 0) continue;
            if (mac_parse(tok[3], mac) != 0) continue;
        } else {
            if (n < 2) continue;
            struct in6_addr t6;
            if (inet_pton(AF_INET6, tok[0], &t6) != 1) continue;
            if (memcmp(&t6, a->addr, 16) != 0) continue;
            if (mac_parse(tok[n - 1], mac) != 0) continue;
        }
        found = 0;
        break;
    }
    fclose(f);
    return found;
}

static int have_mac(const uint8_t mac[6]) {
    static const uint8_t zero[6] = {0, 0, 0, 0, 0, 0};
    return memcmp(mac, zero, 6) != 0;
}

int validate_backends(struct service *svc) {
    int rc = 0;
    for (int i = 0; i < svc->nbacks; i++) {
        struct backend *b = &svc->backs[i];
        if (b->mac_learned) {
            uint8_t lm[6];
            uint16_t st = 0;
            /* Retry, and ask the kernel to resolve rather than only reading:
             * a cold neighbour table is ordinary at startup, and one failed
             * lookup is not evidence that the address is unreachable. */
            if (neigh_get(&b->addr, b->ifindex_hint, lm, &st) != 0 &&
                neighbour_resolve(&b->addr, b->ifindex_hint, 4, 250) == 0)
                neigh_get(&b->addr, b->ifindex_hint, lm, &st);
            if (have_mac(lm)) {
                memcpy(b->mac, lm, 6);
                svc->st.mac_learned++;
                char lb[32];
                mac_format(lm, lb, sizeof(lb));
                log_msg("backend %s: mac=auto learned %s (neighbour state %s)",
                        b->id, lb, neigh_state_name(st));
                continue;
            }
            /* Nothing usable. Separate "not yet resolved" from "will never
             * resolve": a FAILED entry means the kernel asked and got nothing,
             * which for a routable address means it is off this segment. */
            uint8_t tmp[6];
            uint16_t fst = 0;
            int seen_any = (neigh_get(&b->addr, 0, tmp, &fst) == 0);
            svc->st.mac_unresolved++;
            if (seen_any) {
                log_err("backend %s: mac=auto but the neighbour entry is %s",
                        b->id, neigh_state_name(fst));
            } else {
                log_err("backend %s: mac=auto could not resolve a hardware "
                        "address. Neighbour resolution only works inside one "
                        "broadcast domain: if this backend is behind a router it "
                        "can never be reached this way, and the answer is "
                        "tunnelled DSR, not more retrying.", b->id);
            }
            rc = -1;
            continue;
        }
        if (!b->mac_configured) {
            log_err("backend %s has no mac. DSR redirects at layer 2, so the "
                    "hardware address is required; without it the only honest "
                    "options are to supply it or to look it up.", b->id);
            rc = -1;
            continue;
        }
        uint8_t seen[6];
        int r = neigh_lookup(&b->addr, seen);
        char sb[32], cb[32];
        mac_format(seen, sb, sizeof(sb));
        mac_format(b->mac, cb, sizeof(cb));
        if (r == 0 && memcmp(seen, b->mac, 6) != 0) {
            log_err("backend %s is configured with mac %s but the neighbour table "
                    "resolves it to %s. Refusing to start: a wrong hardware address "
                    "is an invisible blackhole, not a recoverable fault.", b->id, cb, sb);
            rc = -1;
        } else if (r == -2) {
            log_msg("backend %s: neighbour table unavailable for IPv6; mac %s was "
                    "not cross-checked", b->id, cb);
        } else if (r < 0) {
            log_msg("backend %s: no neighbour entry yet; mac %s was not "
                    "cross-checked. Send one packet to it and reload to re-check.",
                    b->id, cb);
        } else {
            log_msg("backend %s: mac %s agrees with the neighbour table", b->id, cb);
        }
    }
    return rc;
}

/* A backend's hardware address changing after startup is the one fault that
 * produces a blackhole with no counter movement and no error anywhere: frames
 * go to an address nobody answers, and udpdist counts them as successfully
 * forwarded. The neighbour notification group tells us instead. */
static void neigh_handle(struct service *svc) {
    struct neigh_entry ents[NEIGH_MAX];
    int ndeleted = 0;
    int n = neigh_watch_drain(ents, NEIGH_MAX, &ndeleted);

    for (int i = 0; i < n; i++) {
        if (!neigh_state_usable(ents[i].state)) continue;
        for (int k = 0; k < svc->nbacks; k++) {
            struct backend *b = &svc->backs[k];
            if (b->addr.family != ents[i].family) continue;
            if (memcmp(b->addr.addr, ents[i].addr,
                       b->addr.family == AF_INET ? 4 : 16) != 0) continue;
            if (!b->mac_learned) {
                /* An explicitly configured address is never silently
                 * rewritten. A change here means the configuration is now
                 * wrong, which is worth refusing to paper over. */
                if (b->mac_configured && memcmp(b->mac, ents[i].mac, 6) != 0) {
                    char ob[32], nb[32];
                    mac_format(b->mac, ob, sizeof(ob));
                    mac_format(ents[i].mac, nb, sizeof(nb));
                    log_err("backend %s: neighbour table now says %s but the "
                            "configuration says %s. Not changing an explicitly "
                            "configured address; the configuration is stale.",
                            b->id, nb, ob);
                }
                continue;
            }
            if (memcmp(b->mac, ents[i].mac, 6) == 0) continue;
            char ob[32], nb[32];
            mac_format(b->mac, ob, sizeof(ob));
            mac_format(ents[i].mac, nb, sizeof(nb));
            memcpy(b->mac, ents[i].mac, 6);
            svc->st.mac_changed++;
            log_msg("backend %s: mac changed %s -> %s, following the neighbour table",
                    b->id, ob, nb);
        }
    }
    if (ndeleted > 0)
        log_msg("neighbour table: %d entries removed; learned addresses are kept "
                "until a new one arrives", ndeleted);
}

static int send_frame(struct service *svc, struct dgram *d, int backend) {
    struct backend *b = &svc->backs[backend];
    int fi = 0;
    for (int i = 0; i < svc->nfronts; i++) {
        if (svc->fronts[i].addr.family == d->ip.dst.family &&
            memcmp(svc->fronts[i].addr.addr, d->ip.dst.addr,
                   (d->ip.dst.family == AF_INET) ? 4 : 16) == 0) {
            fi = svc->fronts[i].iface;
            break;
        }
    }
    struct iface *ifc = &svc->ifaces[fi];
    if (ifc->tx_fd < 0) {
        svc->st.send_failed++;
        return -1;
    }
    uint8_t out[RXBUF];
    size_t l3 = d->frame_len - d->l2_len;
    if (l3 + ETHER_HDR_LEN > sizeof(out)) {
        svc->st.oversized++;
        return -1;
    }
    /* Build the whole Ethernet frame here and let the kernel transmit it
     * verbatim. Measured: this kernel does not synthesise a layer 2 header for
     * an AF_PACKET send at all, so handing it only the layer 3 payload puts the
     * IP header on the wire as a destination address. Conversely, setting
     * sll_halen on a bound socket makes the kernel prepend its own header and
     * the backend discards the doubled result. sll_halen must therefore be 0
     * with a complete frame in the buffer. */
    uint8_t *o = out;
    memcpy(o, b->mac, 6);
    memcpy(o + 6, ifc->mac, 6);
    uint16_t et = (d->ip.family == AF_INET) ? ETH_P_IP : ETH_P_IPV6;
    o[12] = (uint8_t)(et >> 8);
    o[13] = (uint8_t)(et & 0xff);
    memcpy(o + ETHER_HDR_LEN, d->frame + d->l2_len, l3);

    struct sockaddr_ll sll;
    memset(&sll, 0, sizeof(sll));
    sll.sll_family = AF_PACKET;
    sll.sll_protocol = htons(ETH_P_ALL);
    sll.sll_ifindex = ifc->index;
    sll.sll_halen = 0;
    ssize_t n = sendto(ifc->tx_fd, out, l3 + ETHER_HDR_LEN, 0,
                       (struct sockaddr *)&sll, sizeof(sll));
    if (n < 0) {
        svc->st.send_failed++;
        return -1;
    }
    b->pkts++;
    b->bytes += (uint64_t)l3;
    svc->st.forwarded++;
    return 0;
}

static void count_parse_fail(struct service *svc, int rc) {
    switch (rc) {
    case -3: svc->st.non_ip++; break;
    case -4: svc->st.not_udp++; break;
    case -5: svc->st.oversized++; break;
    case -6: svc->st.bad_checksum++; break;
    case -7: svc->st.multicast++; break;
    case -8: svc->st.broadcast++; break;
    case -2: svc->st.truncated++; break;
    default:  svc->st.malformed++; break;
    }
}

/* A frame whose source hardware address is one of ours came from this host.
 * The kernel's OUTGOING flag is not a sufficient filter on its own: a frame we
 * re-emit can come back through the bridge, and re-processing it would forward
 * our own output for ever. */
static int frame_is_ours(const struct service *svc, const uint8_t *frame) {
    if (frame == NULL || svc == NULL) return 0;
    for (int i = 0; i < svc->nifaces; i++)
        if (memcmp(frame + 6, svc->ifaces[i].mac, 6) == 0) return 1;
    return 0;
}

static void process_frame(struct service *svc, uint8_t *buf, size_t len, int truncated,
                          int csum_ready) {
    svc->st.rx++;
    if (truncated) {
        svc->st.truncated++;
        return;
    }
    struct dgram d;
    int rc = frame_parse(buf, len, svc->max_datagram, csum_ready, &d);
    if (rc != 0) {
        count_parse_fail(svc, rc);
        return;
    }

    if (d.ip.frag == FRAG_SUBSEQUENT) {
        if (!frame_addr_is_frontend(svc, &d.ip.dst)) {
            svc->st.not_ours++;
            return;
        }
        int b = frag_lookup(svc, &d.ip);
        if (b < 0) {
            svc->st.orphan_fragment++;
            return;
        }
        svc->st.frag_subsequent++;
        if (!svc->backs[b].healthy) {
            svc->st.no_backend++;
            return;
        }
        send_frame(svc, &d, b);
        return;
    }

    int fi = frame_find_frontend(svc, &d.ip);
    if (fi < 0) {
        svc->st.not_ours++;
        return;
    }
    struct frontend *f = &svc->fronts[fi];
    f->rx++;

    int backend;
    if (d.ip.frag == FRAG_INITIAL) {
        backend = hrw_select(svc, &d.ip.src, d.ip.src_port, &d.ip.dst, d.ip.dst_port);
        if (backend < 0) { svc->st.no_backend++; f->no_backend++; return; }
        if (frag_insert(svc, &d.ip, backend) != 0) {
            svc->st.fragment_table_full++;
        }
        svc->st.frag_initial++;
        f->frag_rx++;
    } else if (f->proto == FRONT_PROTO_QUIC) {
        int state = QUIC_STATE_UDP;
        backend = quic_select(svc, f, &d.ip, &state);
        if (backend < 0) { svc->st.no_backend++; f->no_backend++; return; }
    } else {
        backend = hrw_select(svc, &d.ip.src, d.ip.src_port, &d.ip.dst, d.ip.dst_port);
        if (backend < 0) { svc->st.no_backend++; f->no_backend++; return; }
    }
    send_frame(svc, &d, backend);
}

static void drain_sinks(struct service *svc) {
    uint8_t junk[2048];
    for (int i = 0; i < svc->nfronts; i++) {
        struct frontend *f = &svc->fronts[i];
        if (f->sink_fd < 0) continue;
        for (;;) {
            ssize_t n = recv(f->sink_fd, junk, sizeof(junk), MSG_DONTWAIT);
            if (n < 0) break;
            f->sink_observed++;
        }
    }
}

static void dump_stats(const struct service *svc) {
    log_msg("=== %s stats ===", svc->name);
    log_msg(" rx=%lu fwd=%lu", (unsigned long)svc->st.rx,
            (unsigned long)svc->st.forwarded);
    log_msg(" drops: non_ip=%lu not_udp=%lu malformed=%lu truncated=%lu "
            "oversized=%lu bad_cksum=%lu multicast=%lu broadcast=%lu not_ours=%lu",
            (unsigned long)svc->st.non_ip, (unsigned long)svc->st.not_udp,
            (unsigned long)svc->st.malformed, (unsigned long)svc->st.truncated,
            (unsigned long)svc->st.oversized, (unsigned long)svc->st.bad_checksum,
            (unsigned long)svc->st.multicast, (unsigned long)svc->st.broadcast,
            (unsigned long)svc->st.not_ours);
    log_msg(" frag: initial=%lu subsequent=%lu orphan=%lu table_full=%lu",
            (unsigned long)svc->st.frag_initial, (unsigned long)svc->st.frag_subsequent,
            (unsigned long)svc->st.orphan_fragment,
            (unsigned long)svc->st.fragment_table_full);
    log_msg(" quic: routable=%lu fallback_hit=%lu fallback_miss=%lu unroutable=%lu "
            "sid_unknown=%lu backend_down=%lu",
            (unsigned long)svc->st.quic_routable,
            (unsigned long)svc->st.quic_fallback_hit,
            (unsigned long)svc->st.quic_fallback_miss,
            (unsigned long)svc->st.quic_unroutable,
            (unsigned long)svc->st.quic_backend_unknown,
            (unsigned long)svc->st.quic_backend_down);
    log_msg(" no_backend=%lu send_failed=%lu self_echo=%lu",
            (unsigned long)svc->st.no_backend, (unsigned long)svc->st.send_failed,
            (unsigned long)svc->st.self_echo);
    for (int i = 0; i < svc->nfronts; i++) {
        const struct frontend *f = &svc->fronts[i];
        log_msg("  frontend %s proto=%s quic_mode=%s rx=%lu fwd_ub=%lu "
                "cid_routable=%lu fb_hit=%lu fb_miss=%lu sink_observed=%lu",
                f->id, f->proto == FRONT_PROTO_QUIC ? "quic" : "udp",
                f->quic_mode == QUIC_MODE_QUIC_LB ? "quic_lb" : "fallback",
                (unsigned long)f->rx, (unsigned long)f->no_backend,
                (unsigned long)f->quic_routable, (unsigned long)f->quic_fallback_hit,
                (unsigned long)f->quic_fallback_miss, (unsigned long)f->sink_observed);
    }
    for (int i = 0; i < svc->nbacks; i++) {
        const struct backend *b = &svc->backs[i];
        char mb[32];
        mac_format(b->mac, mb, sizeof(mb));
        log_msg("  backend %s mac=%s pkts=%lu bytes=%lu %s", b->id, mb,
                (unsigned long)b->pkts, (unsigned long)b->bytes,
                b->healthy ? "healthy" : "DOWN");
    }
}

static void usage(void) {
    fprintf(stderr,
        "Usage: %s [--syslog] [--check] <service_name> | -c <config_path>\n"
        "  service_name loads /etc/saphira/udpdist/<service_name>.conf\n"
        "  --check   validate the configuration and exit\n"
        "Signals: SIGHUP reload, SIGUSR1 statistics, SIGTERM/SIGINT exit\n", PROG);
}

static void preserve_stats(struct service *dst, const struct service *src) {
    dst->st = src->st;
    for (int i = 0; i < dst->nfronts && i < src->nfronts; i++) {
        dst->fronts[i].rx = src->fronts[i].rx;
        dst->fronts[i].no_backend = src->fronts[i].no_backend;
        dst->fronts[i].quic_routable = src->fronts[i].quic_routable;
        dst->fronts[i].quic_fallback_hit = src->fronts[i].quic_fallback_hit;
        dst->fronts[i].quic_fallback_miss = src->fronts[i].quic_fallback_miss;
        dst->fronts[i].quic_unroutable = src->fronts[i].quic_unroutable;
        dst->fronts[i].quic_backend_unknown = src->fronts[i].quic_backend_unknown;
        dst->fronts[i].quic_backend_down = src->fronts[i].quic_backend_down;
        dst->fronts[i].sink_observed = src->fronts[i].sink_observed;
    }
    for (int i = 0; i < dst->nbacks && i < src->nbacks; i++) {
        dst->backs[i].pkts = src->backs[i].pkts;
        dst->backs[i].bytes = src->backs[i].bytes;
    }
}

/* Moves the descriptors the new configuration reuses out of the old one. This
 * is a transfer of ownership, not an alias: the source is left holding -1 so
 * that neither the success path nor the failure path can close a descriptor the
 * live configuration is now using. Aliasing here closes the receive and send
 * sockets the instant a reload succeeds, and forwarding stops silently. */
static int carry_fds(struct service *dst, struct service *src) {
    for (int i = 0; i < dst->nifaces; i++) {
        for (int j = 0; j < src->nifaces; j++) {
            if (strcmp(dst->ifaces[i].name, src->ifaces[j].name) == 0) {
                dst->ifaces[i].rx_fd = src->ifaces[j].rx_fd;
                dst->ifaces[i].tx_fd = src->ifaces[j].tx_fd;
                src->ifaces[j].rx_fd = -1;
                src->ifaces[j].tx_fd = -1;
                break;
            }
        }
        if (dst->ifaces[i].rx_fd < 0) {
            log_err("reload needs a new AF_PACKET socket on '%s', which cannot be "
                    "created after the privilege drop; keeping the old configuration",
                    dst->ifaces[i].name);
            return -1;
        }
    }
    for (int i = 0; i < dst->nfronts; i++) {
        for (int j = 0; j < src->nfronts; j++) {
            char a[UD_ID_MAX], b[UD_ID_MAX];
            addr_id(&dst->fronts[i].addr, a, sizeof(a));
            addr_id(&src->fronts[j].addr, b, sizeof(b));
            if (strcmp(a, b) == 0) {
                dst->fronts[i].sink_fd = src->fronts[j].sink_fd;
                src->fronts[j].sink_fd = -1;
                break;
            }
        }
        if (dst->fronts[i].sink_fd < 0) {
            const char *id = dst->fronts[i].id;
            int fd = socket(dst->fronts[i].addr.family, SOCK_DGRAM, IPPROTO_UDP);
            if (fd < 0) {
                log_err("reload needs a new sink socket for %s: %s; keeping the old "
                        "configuration", id, strerror(errno));
                return -1;
            }
            if (bind(fd, (struct sockaddr *)&dst->fronts[i].addr,
                     dst->fronts[i].addr.family == AF_INET
                         ? sizeof(struct sockaddr_in)
                         : sizeof(struct sockaddr_in6)) != 0) {
                log_err("reload needs a new sink bind for %s, which is not permitted "
                        "after the privilege drop; keeping the old configuration", id);
                close(fd);
                return -1;
            }
            set_nonblock(fd);
            dst->fronts[i].sink_fd = fd;
        }
    }
    return 0;
}

int main(int argc, char **argv) {
    const char *config_path = NULL;
    const char *service_name = NULL;
    int check_only = 0;
    char config_buf[512];
    char name_buf[UD_NAME_MAX] = "";

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            usage();
            return 0;
        } else if (strcmp(argv[i], "--syslog") == 0) {
            opt_syslog = 1;
        } else if (strcmp(argv[i], "--check") == 0) {
            check_only = 1;
        } else if (strcmp(argv[i], "-c") == 0) {
            if (i + 1 >= argc) { usage(); return 1; }
            config_path = argv[++i];
        } else if (argv[i][0] == '-') {
            fprintf(stderr, "unknown option %s\n", argv[i]);
            usage();
            return 1;
        } else {
            service_name = argv[i];
            break;
        }
    }

    if (!config_path) {
        if (!service_name) { usage(); return 1; }
        if (!name_is_valid(service_name)) { log_err("invalid service name"); return 1; }
        snprintf(config_buf, sizeof(config_buf), "/etc/saphira/udpdist/%s.conf",
                 service_name);
        config_path = config_buf;
        snprintf(name_buf, sizeof(name_buf), "%s", service_name);
    } else {
        const char *base = strrchr(config_path, '/');
        base = base ? base + 1 : config_path;
        size_t blen = strlen(base);
        if (blen > 5 && strcmp(base + blen - 5, ".conf") == 0) blen -= 5;
        if (blen >= sizeof(name_buf)) blen = sizeof(name_buf) - 1;
        memcpy(name_buf, base, blen);
        name_buf[blen] = '\0';
        if (name_buf[0] == '\0') snprintf(name_buf, sizeof(name_buf), "%s", PROG);
        if (!name_is_valid(name_buf)) {
            log_err("invalid service name derived from the configuration path");
            return 1;
        }
    }

    struct service svc;
    if (config_load(config_path, &svc, name_buf) != 0) return 1;

    if (check_only) {
        printf("%s: configuration valid: %d frontend(s), %d backend(s), "
               "%d interface(s), %d quic config(s)\n",
               config_path, svc.nfronts, svc.nbacks, svc.nifaces, svc.nquic);
        return 0;
    }

    if (opt_syslog) openlog(PROG, LOG_PID, LOG_DAEMON);

    log_msg("%s: starting service %s: %d frontend(s), %d backend(s)",
            PROG, svc.name, svc.nfronts, svc.nbacks);
    for (int i = 0; i < svc.nfronts; i++) {
        struct frontend *f = &svc.fronts[i];
        log_msg("  frontend %s proto=%s quic_mode=%s on %s", f->id,
                f->proto == FRONT_PROTO_QUIC ? "quic" : "udp",
                f->quic_mode == QUIC_MODE_QUIC_LB ? "quic_lb" : "fallback",
                svc.ifaces[f->iface].name);
    }
    for (int i = 0; i < svc.nbacks; i++) {
        char mb[32];
        mac_format(svc.backs[i].mac, mb, sizeof(mb));
        log_msg("  backend %s mac=%s%s", svc.backs[i].id, mb,
                svc.backs[i].quic_sid_set ? "" : "");
    }

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = sig_handler;
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGHUP, &sa, NULL);
    sigaction(SIGUSR1, &sa, NULL);
    signal(SIGPIPE, SIG_IGN);

    if (prepare(&svc) != 0) return 1;

    if (!svc.skip_csum_check) {
        int bad = 0;
        for (int i = 0; i < svc.nifaces; i++) {
            char what[8] = "";
            int r = csum_offload_is_on(svc.ifaces[i].name, what, sizeof(what));
            if (r == 1) {
                log_err("interface '%s' has %s checksum offload enabled. This "
                        "distributor forwards received bytes unchanged, so an "
                        "unfinished transport checksum reaches the backend and is "
                        "discarded there: every packet would be lost while this "
                        "daemon reported a successful forward.", svc.ifaces[i].name, what);
                log_err("fix: ethtool -K %s tx off rx off   (or set "
                        "skip_csum_offload_check=1 if the platform is known good)",
                        svc.ifaces[i].name);
                bad = 1;
            }
        }
        if (bad) return 1;
    }

    if (neigh_watch_open() < 0)
        log_msg("neighbour change notification unavailable (%s); learned mac "
                "addresses will not be tracked after startup", strerror(errno));
    if (validate_backends(&svc) != 0) return 1;
    if (health_open(&svc) != 0) return 1;

    /* Prove the health mechanism works before accepting any traffic. A host with
     * an empty net.ipv4.ping_group_range cannot deliver an echo reply to an
     * unprivileged ping socket, and the failure would otherwise appear as every
     * backend being marked down and every packet dropped, with no cause. */
    if (!svc.skip_health_check) {
        int ok_count = health_selftest(&svc);
        if (ok_count == 0) {
            log_err("no backend answered an ICMP echo probe before any traffic was "
                    "accepted. Without working health checks this daemon would mark "
                    "every backend down and silently drop all traffic.");
            log_err("on Linux, unprivileged ICMP needs a non-empty range, e.g. "
                    "sysctl -w net.ipv4.ping_group_range='0 2147483647'");
            log_err("set allow_unverified_health=1 to start anyway and accept that "
                    "health state is not observable");
            return 1;
        }
        log_msg("health verified: %d of %d backends answered an ICMP echo probe",
                ok_count, svc.nbacks);
    }

    int tfd = timerfd_create(CLOCK_MONOTONIC, TFD_NONBLOCK);
    if (tfd >= 0) {
        struct itimerspec its;
        memset(&its, 0, sizeof(its));
        its.it_interval.tv_sec = HEALTH_INTERVAL_SEC;
        its.it_value.tv_sec = 1;
        timerfd_settime(tfd, 0, &its, NULL);
    }

    if (drop_privileges() != 0) return 1;

    {
        int fd = open(config_path, O_RDONLY);
        if (fd < 0) {
            log_err("cannot re-read %s as %s: %s. Refusing to start rather than run "
                    "reload-blind; apply: chgrp -R %s /etc/saphira && chmod 0750 "
                    "/etc/saphira", config_path, UDPDIST_USER, strerror(errno),
                    UDPDIST_GROUP);
            return 1;
        }
        close(fd);
    }

    log_msg("%s: ready (uid %d)", svc.name, (int)getuid());

    uint8_t *buf = malloc(RXBUF);
    if (!buf) {
        log_err("out of memory");
        return 1;
    }

    while (!do_quit) {
        if (do_reload) {
            do_reload = 0;
            log_msg("%s: reloading %s", svc.name, svc.config_path);
            struct service nsvc;
            if (config_load(svc.config_path, &nsvc, svc.name) == 0) {
                for (int i = 0; i < nsvc.nifaces; i++) {
                    nsvc.ifaces[i].index = if_nametoindex(nsvc.ifaces[i].name);
                    if (nsvc.ifaces[i].index == 0)
                        nsvc.ifaces[i].index = -1;
                    else
                        if_mac(nsvc.ifaces[i].name, nsvc.ifaces[i].mac);
                }
                if (carry_fds(&nsvc, &svc) == 0) {
                    preserve_stats(&nsvc, &svc);
                    svc = nsvc;
                    log_msg("%s: reloaded %d frontend(s), %d backend(s)",
                            svc.name, svc.nfronts, svc.nbacks);
                } else {
                    /* Only descriptors this attempt created are still open; the
                     * rest were moved back out of reach by carry_fds. */
                    for (int i = 0; i < nsvc.nfronts; i++)
                        if (nsvc.fronts[i].sink_fd >= 0) close(nsvc.fronts[i].sink_fd);
                    nsvc.nfronts = 0;
                    for (int i = 0; i < nsvc.nifaces; i++) {
                        if (nsvc.ifaces[i].rx_fd >= 0) close(nsvc.ifaces[i].rx_fd);
                        if (nsvc.ifaces[i].tx_fd >= 0) close(nsvc.ifaces[i].tx_fd);
                    }
                }
            } else {
                log_err("reload failed; keeping the old configuration");
            }
        }
        if (do_dump) { do_dump = 0; dump_stats(&svc); }

        struct pollfd pfd[UD_MAX_IFACES + UD_MAX_FRONTS + 4];
        int npfd = 0;
        int map_kind[UD_MAX_IFACES + UD_MAX_FRONTS + 4];

        for (int i = 0; i < svc.nifaces; i++) {
            if (svc.ifaces[i].rx_fd < 0) continue;
            pfd[npfd].fd = svc.ifaces[i].rx_fd;
            pfd[npfd].events = POLLIN;
            map_kind[npfd] = 0;
            npfd++;
        }
        for (int i = 0; i < svc.nfronts; i++) {
            if (svc.fronts[i].sink_fd < 0) continue;
            pfd[npfd].fd = svc.fronts[i].sink_fd;
            pfd[npfd].events = POLLIN;
            map_kind[npfd] = 1;
            npfd++;
        }
        int hfds[2];
        int nh = health_fds(hfds);
        for (int i = 0; i < nh; i++) {
            pfd[npfd].fd = hfds[i];
            pfd[npfd].events = POLLIN;
            map_kind[npfd] = 2;
            npfd++;
        }
        if (tfd >= 0) {
            pfd[npfd].fd = tfd;
            pfd[npfd].events = POLLIN;
            map_kind[npfd] = 3;
            npfd++;
        }
        int nfd = neigh_watch_open_once();
        if (nfd >= 0) {
            pfd[npfd].fd = nfd;
            pfd[npfd].events = POLLIN;
            map_kind[npfd] = 4;
            npfd++;
        }

        health_tick(&svc);
        health_timeout(&svc);
        frag_expire(&svc, now_ms());
        quic_fb_expire(&svc, now_ms());

        int pr = poll(pfd, npfd, 200);
        if (pr < 0) {
            if (errno == EINTR) continue;
            log_err("poll: %s", strerror(errno));
            break;
        }
        for (int k = 0; k < npfd; k++) {
            if (!(pfd[k].revents & (POLLIN | POLLERR))) continue;
            if (map_kind[k] == 4) { neigh_handle(&svc); continue; }
            if (map_kind[k] == 0) {
                for (;;) {
                    struct iovec iov;
                    struct msghdr mh;
                    struct sockaddr_ll sll;
                    memset(&mh, 0, sizeof(mh));
                    memset(&sll, 0, sizeof(sll));
                    iov.iov_base = buf;
                    iov.iov_len = RXBUF;
                    mh.msg_name = &sll;
                    mh.msg_namelen = sizeof(sll);
                    mh.msg_iov = &iov;
                    mh.msg_iovlen = 1;
                    uint8_t cbuf[64];
                    mh.msg_control = cbuf;
                    mh.msg_controllen = sizeof(cbuf);
                    ssize_t n = recvmsg(pfd[k].fd, &mh, MSG_DONTWAIT);
                    if (n < 0) {
                        if (errno == EINTR) continue;
                        break;
                    }
                    if ((size_t)n >= RXBUF) {
                        svc.st.truncated++;
                        continue;
                    }
                    int csum_ready = 1, outgoing = 0;
                    for (struct cmsghdr *c = CMSG_FIRSTHDR(&mh); c;
                         c = CMSG_NXTHDR(&mh, c)) {
                        if (c->cmsg_level == SOL_PACKET &&
                            c->cmsg_type == PACKET_AUXDATA &&
                            c->cmsg_len >= CMSG_LEN(sizeof(struct tpacket_auxdata_local))) {
                            struct tpacket_auxdata_local aux;
                            memcpy(&aux, CMSG_DATA(c), sizeof(aux));
                            if (aux.tp_status & TP_STATUS_CSUMNOTREADY_LOCAL)
                                csum_ready = 0;
                            if (aux.tp_status & TP_STATUS_OUTGOING_LOCAL)
                                outgoing = 1;
                        }
                    }
                    if (outgoing || frame_is_ours(&svc, buf)) {
                        svc.st.self_echo++;
                        continue;
                    }
                    process_frame(&svc, buf, (size_t)n, 0, csum_ready);
                }
            } else if (map_kind[k] == 1) {
                drain_sinks(&svc);
            } else if (map_kind[k] == 2) {
                health_recv(&svc, pfd[k].fd);
            } else if (map_kind[k] == 3) {
                uint64_t exp;
                ssize_t r = read(tfd, &exp, sizeof(exp));
                (void)r;
            }
        }
    }

    log_msg("%s: shutting down", svc.name);
    dump_stats(&svc);
    close_sinks(&svc);
    close_ifaces(&svc);
    health_close();
    if (tfd >= 0) close(tfd);
    free(buf);
    return 0;
}

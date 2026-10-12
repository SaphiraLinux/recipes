/*
 * saphira-bridge - port I/O and the forwarding loop.
 * BUSL-1.1, see LICENSE.
 *
 * Transport only. Where a frame goes was already decided in fwd.c; this file
 * gets bytes off one port and onto the ports that decision named.
 */
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <net/if.h>
#include <poll.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <net/ethernet.h>
#include <netinet/in.h>
#include <linux/if_packet.h>
#include <linux/virtio_net.h>
#include <linux/if_ether.h>
#include <linux/if_packet.h>
#include <linux/virtio_net.h>
#include <time.h>

#include "bridge.h"

/* This kernel's <linux/if_packet.h> does not define TP_STATUS_OUTGOING, though
 * the value is stable and is what the kernel sets in tpacket_auxdata for a
 * frame this host transmitted. Defined here rather than including a second
 * header that would conflict, matching what saphira-udpdist already does. */
#ifndef TP_STATUS_OUTGOING
#define TP_STATUS_OUTGOING 0x00000004
#endif

static volatile sig_atomic_t want_quit;
static volatile sig_atomic_t want_reload;
static volatile sig_atomic_t want_dump;
static int wake_pipe[2] = {-1, -1};

static void on_signal(int sig) {
    if (sig == SIGTERM || sig == SIGINT) want_quit = 1;
    else if (sig == SIGHUP) want_reload = 1;
    else if (sig == SIGUSR1) want_dump = 1;
    if (wake_pipe[1] >= 0) {
        char c = 1;
        ssize_t n = write(wake_pipe[1], &c, 1);
        (void)n;
    }
}

static time_t now_s(void) { return time(NULL); }

void br_count_reason(struct br_stats *st, enum br_reason r) {
    st->dropped++;
    switch (r) {
    case BR_R_TOO_SHORT: st->too_short++; break;
    case BR_R_VLAN_TAGGED: st->vlan_tagged++; break;
    case BR_R_RESERVED: st->reserved++; break;
    case BR_R_TX_FAILED: st->tx_failed++; break;
    case BR_R_NO_EGRESS: st->no_egress++; break;
    case BR_R_NONE: break;
    }
}

/* The hardware address is only used for log lines, so a failure here must not
 * be silent: a bridge that reports 00:00:00:00:00:00 for a port looks like it
 * has no hardware address at all, which is exactly the sort of cosmetic lie
 * that makes a diagnostic useless. It is also queried on its own AF_INET
 * socket, because SIOCGIFHWADDR is not dependable on an AF_PACKET descriptor. */
static int port_hwaddr(struct br_port *p) {
    struct ifreq ifr;
    int s = socket(AF_INET, SOCK_DGRAM, 0);
    int rc = -1;
    if (s < 0) return -1;
    memset(&ifr, 0, sizeof(ifr));
    snprintf(ifr.ifr_name, sizeof(ifr.ifr_name), "%s", p->name);
    if (ioctl(s, SIOCGIFHWADDR, &ifr) == 0) {
        memcpy(p->hwaddr, ifr.ifr_hwaddr.sa_data, BR_MACLEN);
        rc = 0;
    }
    close(s);
    return rc;
}

int br_open_port(struct br_port *p) {
    struct sockaddr_ll sll;
    int fd;

    fd = socket(AF_PACKET, SOCK_RAW, htons(ETH_P_ALL));
    if (fd < 0) {
        br_log_err("%s: socket: %s", p->name, strerror(errno));
        return -1;
    }
    p->ifindex = if_nametoindex(p->name);
    if (p->ifindex == 0) {
        br_log_err("%s: no such interface", p->name);
        close(fd);
        p->fd = -1;
        return -1;
    }

    memset(&sll, 0, sizeof(sll));
    sll.sll_family = AF_PACKET;
    sll.sll_protocol = htons(ETH_P_ALL);
    sll.sll_ifindex = p->ifindex;
    if (bind(fd, (struct sockaddr *)&sll, sizeof(sll)) != 0) {
        br_log_err("%s: bind: %s", p->name, strerror(errno));
        close(fd);
        p->fd = -1;
        p->ifindex = -1;
        return -1;
    }
    if (port_hwaddr(p) != 0)
        br_log_err("%s: cannot read this port's hardware address; counters are "
                   "unaffected but log lines will show it as zero", p->name);

    /* A promiscuous socket also sees the frames this bridge transmits. Without
     * this, a frame sent out one port is read back on that port, judged to
     * need forwarding, and sent out the other ports: a forwarding loop that
     * turns a quiet segment into hundreds of thousands of frames a second.
     * The auxiliary data is how a frame is identified as our own. */
    {
        int one = 1;
        /* Kept only as a diagnostic now. It is not trusted for direction: the
         * auxdata status word is not populated for every receive path, and a
         * direction test that silently reports "not ours" when it simply does
         * not know is worse than no test at all. */
        if (setsockopt(fd, SOL_PACKET, PACKET_AUXDATA, &one, sizeof(one)) != 0)
            br_log_err("%s: PACKET_AUXDATA: %s", p->name, strerror(errno));
    }
    /* Deferred-checksum metadata is carried across the userspace hop rather
     * than computed here. A sender that offloads hands over a frame whose
     * transport checksum is not yet written; the kernel tells us so both in the
     * auxdata and in a virtio_net_hdr that names exactly where the work is
     * (csum_start, csum_offset). Passing that header back out lets the egress
     * path finish the job, so the bridge never has to parse IP. */
    p->vnet_rx = 0;
    {
        int one = 1;
        if (setsockopt(fd, SOL_PACKET, PACKET_VNET_HDR, &one, sizeof(one)) == 0)
            p->vnet_rx = 1;
        else
            br_log_msg("%s: PACKET_VNET_HDR not accepted for receive (%s); "
                       "frames with a deferred checksum will be refused rather "
                       "than forwarded incomplete", p->name, strerror(errno));
    }

    p->ignore_outgoing = 0;
    if (p->want_ignore_outgoing) {
        int one = 1;
        if (setsockopt(fd, SOL_PACKET, PACKET_IGNORE_OUTGOING, &one, sizeof(one)) == 0)
            p->ignore_outgoing = 1;
        else
            br_log_err("%s: PACKET_IGNORE_OUTGOING: %s; falling back to the "
                       "sll_pkttype check, which is authoritative anyway",
                       p->name, strerror(errno));
    }

    fcntl(fd, F_SETFL, O_NONBLOCK);
    p->fd = fd;

    /* A separate descriptor for transmit, which is what saphira-udpdist does
     * and for a measured reason: reusing the descriptor that is also being
     * drained for received frames is fragile on this kernel, and the cost of a
     * second socket is a few kilobytes. A bridge whose writes silently vanish
     * is the worst possible failure for this daemon, so the proven arrangement
     * is used rather than the tidy one. */
    p->tx_fd = socket(AF_PACKET, SOCK_RAW, htons(ETH_P_ALL));
    if (p->tx_fd < 0) {
        br_log_err("%s: transmit socket: %s", p->name, strerror(errno));
        close(fd);
        p->fd = -1;
        return -1;
    }
    p->vnet_tx = 0;
    if (p->tx_fd >= 0) {
        int one = 1;
        if (setsockopt(p->tx_fd, SOL_PACKET, PACKET_VNET_HDR, &one, sizeof(one)) == 0)
            p->vnet_tx = 1;
        else
            br_log_err("%s: PACKET_VNET_HDR not accepted for transmit: %s",
                       p->name, strerror(errno));
    }
    return 0;
}

int br_close_port(struct br_port *p) {
    if (p->fd >= 0) { close(p->fd); p->fd = -1; }
    if (p->tx_fd >= 0) { close(p->tx_fd); p->tx_fd = -1; }
    p->vnet_rx = 0;
    p->vnet_tx = 0;
    p->ifindex = -1;
    return 0;
}

int br_set_promiscuous(struct br_port *p) {
    struct packet_mreq mreq;
    memset(&mreq, 0, sizeof(mreq));
    mreq.mr_ifindex = p->ifindex;
    mreq.mr_type = PACKET_MR_PROMISC;
    if (setsockopt(p->fd, SOL_PACKET, PACKET_ADD_MEMBERSHIP, &mreq, sizeof(mreq)) != 0) {
        br_log_err("%s: cannot enter promiscuous mode: %s. A bridge needs to see "
                   "frames that are not addressed to it, so this is fatal rather "
                   "than a warning.", p->name, strerror(errno));
        return -1;
    }
    return 0;
}

/* The whole Ethernet frame is written, unmodified, with sll_halen left at zero.
 * Handing the socket a payload and letting it synthesise a header would be
 * tidier in principle, but on this kernel a bound AF_PACKET socket with
 * sll_halen set prepends a second header to the frame it was given - so the
 * bytes go out exactly as they arrived, and what went in is what arrives. */
int br_send_frame(struct br_port *p, const uint8_t *frame, size_t len,
                  const struct virtio_net_hdr *vh) {
    struct sockaddr_ll sll;
    ssize_t n;
    int want = vh != NULL && (vh->flags & VIRTIO_NET_HDR_F_NEEDS_CSUM);
    uint8_t out[BR_RX_BUFSZ + sizeof(struct virtio_net_hdr)];
    const void *buf = frame;
    size_t total = len;

    if (p->tx_fd < 0) return -1;

    /* A frame whose checksum the sender deferred must not leave without that
     * fact, and must not be sent to a port that cannot accept the header. Either
     * the metadata goes with it or the frame does not go. */
    if (want && !p->vnet_tx) return -2;

    /* Once a socket is in PACKET_VNET_HDR mode the kernel reserves the header on
     * every send, not only on the sends that have one. Measured the hard way:
     * prepending it only for deferred frames silently ate the first twelve
     * bytes of every ordinary frame and the segment stopped working. A zeroed
     * header is the correct thing to send for a frame with nothing to defer. */
    if (p->vnet_tx) {
        if (len + sizeof(struct virtio_net_hdr) > sizeof(out)) return -1;
        if (want)
            memcpy(out, vh, sizeof(struct virtio_net_hdr));
        else
            memset(out, 0, sizeof(struct virtio_net_hdr));
        memcpy(out + sizeof(struct virtio_net_hdr), frame, len);
        buf = out;
        total = len + sizeof(struct virtio_net_hdr);
    } else if (want) {
        return -2;
    }

    memset(&sll, 0, sizeof(sll));
    sll.sll_family = AF_PACKET;
    sll.sll_protocol = htons(ETH_P_ALL);
    sll.sll_ifindex = p->ifindex;
    sll.sll_halen = 0;

    n = sendto(p->tx_fd, buf, total, 0, (struct sockaddr *)&sll, sizeof(sll));
    if (n < 0 || (size_t)n != total) return -1;
    return 0;
}

/* "forwarded" counts frames, not port writes. A flood of one frame onto three
 * ports is one forwarded frame and three transmissions; counting the writes
 * instead made the counters impossible to reconcile, and a counter set that
 * does not add up is worse than no counter set at all. Per-port tx counts the
 * writes. */
static void emit(struct br_config *cfg, int skip, const uint8_t *frame,
                 size_t len, struct br_stats *st,
                 const struct virtio_net_hdr *vh) {
    int sent = 0;
    for (int i = 0; i < cfg->nports; i++) {
        if (i == skip) continue;      /* never back out the ingress port */
        int rc = br_send_frame(&cfg->ports[i], frame, len, vh);
        if (rc == 0) {
            cfg->ports[i].tx++;
            sent++;
            if (vh && (vh->flags & VIRTIO_NET_HDR_F_NEEDS_CSUM)) st->deferred_carried++;
        } else if (rc == -2) {
            /* Cannot be forwarded without losing the deferred checksum. */
            st->deferred_refused++;
            st->dropped++;
        } else {
            cfg->ports[i].tx_failed++;
            st->tx_failed++;
        }
    }
    /* Counted only if a port actually took it, so that
     * forwarded == unicast + flooded stays an identity rather than an
     * approximation. A flood that reached nothing is not a flood. */
    if (sent > 0) {
        st->flooded++;
        st->forwarded++;
    }
}

static void dump_stats(const struct br_config *cfg, const struct br_stats *st,
                       const struct br_cam *cam) {
    printf("%s: rx=%llu forwarded=%llu (unicast=%llu flooded=%llu)\n",
           cfg->svcname, (unsigned long long)st->rx,
           (unsigned long long)st->forwarded,
           (unsigned long long)st->unicast,
           (unsigned long long)st->flooded);
    printf(" drops: total=%llu too_short=%llu vlan_tagged=%llu reserved=%llu "
           "no_egress=%llu tx_failed=%llu source_not_learned=%llu self_echo=%llu\n",
           (unsigned long long)st->dropped, (unsigned long long)st->too_short,
           (unsigned long long)st->vlan_tagged, (unsigned long long)st->reserved,
           (unsigned long long)st->no_egress, (unsigned long long)st->tx_failed,
           (unsigned long long)st->source_not_learned,
           (unsigned long long)st->self_echo);
    printf(" direction: self_echo=%llu (sll_pkttype) auxdata_outgoing=%llu "
           "ignore_outgoing=%d\n",
           (unsigned long long)st->self_echo,
           (unsigned long long)st->auxdata_outgoing,
           (int)st->ignore_outgoing_effective);
    printf(" deferred: in=%llu carried=%llu refused=%llu  vnet_hdr=%s\n",
           (unsigned long long)st->deferred_in,
           (unsigned long long)st->deferred_carried,
           (unsigned long long)st->deferred_refused,
           st->vnet_hdr ? "on" : "off");
    printf(" auxdata: csumnotready=%llu csum_valid=%llu vlan_valid=%llu "
           "vlan_tpid_valid=%llu\n",
           (unsigned long long)st->aux_csumnotready,
           (unsigned long long)st->aux_csum_valid,
           (unsigned long long)st->aux_vlan_valid,
           (unsigned long long)st->aux_vlan_tpid_valid);
    printf(" pkttype: host=%llu broadcast=%llu multicast=%llu otherhost=%llu "
           "outgoing=%llu unknown=%llu\n",
           (unsigned long long)st->pkttype_host,
           (unsigned long long)st->pkttype_broadcast,
           (unsigned long long)st->pkttype_multicast,
           (unsigned long long)st->pkttype_otherhost,
           (unsigned long long)st->pkttype_outgoing,
           (unsigned long long)st->pkttype_unknown);
    printf(" cam: entries=%d/%d learnt=%llu moved=%llu expired=%llu evicted=%llu\n",
           br_cam_count(cam), cfg->max_entries, (unsigned long long)cam->learnt,
           (unsigned long long)cam->moved, (unsigned long long)cam->expired,
           (unsigned long long)cam->evicted);
    for (int i = 0; i < cfg->nports; i++) {
        char mac[32];
        br_mac_format(cfg->ports[i].hwaddr, mac, sizeof(mac));
        printf("  port %-10s index=%d mac=%s rx=%llu tx=%llu tx_failed=%llu\n",
               cfg->ports[i].name, i, mac, (unsigned long long)cfg->ports[i].rx,
               (unsigned long long)cfg->ports[i].tx,
               (unsigned long long)cfg->ports[i].tx_failed);
    }
    fflush(stdout);
}

static int open_all(struct br_config *cfg) {
    for (int i = 0; i < cfg->nports; i++) {
        cfg->ports[i].want_ignore_outgoing = cfg->ignore_outgoing;
        if (br_open_port(&cfg->ports[i]) != 0) return -1;
        if (cfg->promiscuous && br_set_promiscuous(&cfg->ports[i]) != 0) return -1;
    }
    return 0;
}

static void close_all(struct br_config *cfg) {
    for (int i = 0; i < cfg->nports; i++) {
        br_close_port(&cfg->ports[i]);
    }
}

int main(int argc, char **argv) {
    const char *path = NULL;
    const char *name = NULL;
    struct br_config cfg;
    struct br_cam cam;
    struct br_stats st;
    int check_only = 0;
    time_t last_sweep = 0;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-c") == 0 && i + 1 < argc) path = argv[++i];
        else if (strcmp(argv[i], "--check") == 0) check_only = 1;
        else if (strcmp(argv[i], "-n") == 0 && i + 1 < argc) name = argv[++i];
        else {
            fprintf(stderr,
                    "usage: saphira-bridge -c CONFIG [-n NAME] [--check]\n"
                    "  -c CONFIG   configuration file\n"
                    "  -n NAME     service name used in log and counter lines\n"
                    "  --check     parse and validate only, then exit\n");
            return 2;
        }
    }
    if (!path) {
        fprintf(stderr, "saphira-bridge: -c CONFIG is required\n");
        return 2;
    }

    if (br_config_load(path, &cfg, name) != 0) return 1;
    if (br_cam_init(&cam, cfg.max_entries, cfg.age_secs) != 0) {
        br_log_err("cannot create a %d entry table", cfg.max_entries);
        return 1;
    }

    if (check_only) {
        printf("saphira-bridge: %s: %d port(s), age=%ds, cam=%d/%d: configuration ok\n",
               cfg.svcname, cfg.nports, cfg.age_secs, br_cam_count(&cam),
               cfg.max_entries);
        br_cam_free(&cam);
        return 0;
    }

    if (pipe(wake_pipe) != 0) {
        br_log_err("pipe: %s", strerror(errno));
        return 1;
    }
    fcntl(wake_pipe[0], F_SETFL, O_NONBLOCK);
    fcntl(wake_pipe[1], F_SETFL, O_NONBLOCK);

    if (open_all(&cfg) != 0) {
        close_all(&cfg);
        return 1;
    }

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = on_signal;
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);
    sigaction(SIGHUP, &sa, NULL);
    sigaction(SIGUSR1, &sa, NULL);
    signal(SIGPIPE, SIG_IGN);

    memset(&st, 0, sizeof(st));
    st.ignore_outgoing_effective = 1;
    st.vnet_hdr = 1;
    for (int i = 0; i < cfg.nports; i++)
        if (!cfg.ports[i].vnet_rx || !cfg.ports[i].vnet_tx) st.vnet_hdr = 0;
    for (int i = 0; i < cfg.nports; i++)
        if (!cfg.ports[i].ignore_outgoing) st.ignore_outgoing_effective = 0;

    if (getuid() == 0) {
        if (setgroups(0, NULL) != 0 && geteuid() == 0)
            br_log_err("setgroups: %s", strerror(errno));
        if (setgid((gid_t)cfg.drop_group) != 0) {
            br_log_err("setgid(%d): %s", cfg.drop_group, strerror(errno));
            close_all(&cfg);
            return 1;
        }
        if (setuid((uid_t)cfg.drop_user) != 0) {
            br_log_err("setuid(%d): %s", cfg.drop_user, strerror(errno));
            close_all(&cfg);
            return 1;
        }
        br_log_msg("dropped privileges: uid=%d gid=%d; no capability is retained",
                   (int)getuid(), (int)getgid());
    }

    for (int i = 0; i < cfg.nports; i++) {
        char mac[32];
        br_mac_format(cfg.ports[i].hwaddr, mac, sizeof(mac));
        br_log_msg("port %s index=%d mac=%s%s", cfg.ports[i].name, i, mac,
                   cfg.promiscuous ? " promiscuous" : "");
    }
    br_log_msg("linux owns ARP, NDP, IP and routing; this moves Ethernet frames "
               "and nothing else");
    br_log_msg("%s: ready (uid %d)", cfg.svcname, (int)getuid());

    while (!want_quit) {
        struct pollfd pfd[BR_MAX_PORTS + 1];
        int npfd = 0;

        for (int i = 0; i < cfg.nports; i++) {
            pfd[npfd].fd = cfg.ports[i].fd;
            pfd[npfd].events = POLLIN;
            pfd[npfd].revents = 0;
            npfd++;
        }
        pfd[npfd].fd = wake_pipe[0];
        pfd[npfd].events = POLLIN;
        pfd[npfd].revents = 0;
        int wake_idx = npfd;
        npfd++;

        int pr = poll(pfd, (nfds_t)npfd, 500);
        if (pr < 0) {
            if (errno == EINTR) continue;
            br_log_err("poll: %s", strerror(errno));
            break;
        }

        if (pfd[wake_idx].revents & POLLIN) {
            char drain[64];
            while (read(wake_pipe[0], drain, sizeof(drain)) > 0) { }
        }

        if (want_dump) {
            want_dump = 0;
            dump_stats(&cfg, &st, &cam);
        }

        if (want_reload) {
            want_reload = 0;
            struct br_config ncfg;
            if (br_config_load(path, &ncfg, name) != 0) {
                br_log_err("reload refused; keeping the running configuration");
            } else if (ncfg.nports != cfg.nports) {
                br_log_err("reload would change the port count from %d to %d, which "
                           "would drop the address table; restart instead",
                           cfg.nports, ncfg.nports);
            } else {
                int same = 1;
                for (int i = 0; i < cfg.nports; i++)
                    if (strcmp(cfg.ports[i].name, ncfg.ports[i].name) != 0) same = 0;
                if (same) {
                    cfg.age_secs = ncfg.age_secs;
                    br_log_msg("reloaded: age=%ds cam=%d", cfg.age_secs, cfg.max_entries);
                } else {
                    br_log_err("reload would change the port set, which would drop "
                               "the address table; restart instead");
                }
            }
        }

        time_t now = now_s();
        if (now != last_sweep) {
            last_sweep = now;
            if (br_cam_age(&cam, now) > 0)
                br_log_msg("cam: swept, %d entries remain", br_cam_count(&cam));
        }

        if (pr <= 0) continue;

        for (int i = 0; i < cfg.nports; i++) {
            if (!(pfd[i].revents & POLLIN)) continue;
            for (;;) {
                /* Room for a virtio_net_hdr in front of the frame. When the
                 * socket is in PACKET_VNET_HDR mode the kernel delivers one and
                 * the frame follows it, so the buffer must start at the header
                 * or the addresses are read from the wrong place entirely. */
                uint8_t buf[BR_RX_BUFSZ + sizeof(struct virtio_net_hdr)];
                uint8_t cbuf[64];
                struct iovec iov;
                struct msghdr mh;
                struct sockaddr_ll from;
                memset(&from, 0, sizeof(from));
                memset(&mh, 0, sizeof(mh));
                iov.iov_base = buf;
                iov.iov_len = sizeof(buf);
                mh.msg_name = &from;
                mh.msg_namelen = sizeof(from);
                mh.msg_iov = &iov;
                mh.msg_iovlen = 1;
                mh.msg_control = cbuf;
                mh.msg_controllen = sizeof(cbuf);
                ssize_t n = recvmsg(cfg.ports[i].fd, &mh, MSG_DONTWAIT);
                if (n < 0) {
                    if (errno == EINTR) continue;
                    break;      /* EAGAIN: drained */
                }

                unsigned aux_outgoing = 0;
                unsigned aux_mac_off = 0;
                struct br_meta meta;
                struct virtio_net_hdr vhstore;
                struct virtio_net_hdr *vh = NULL;
                size_t off = 0;
                memset(&meta, 0, sizeof(meta));
                memset(&vhstore, 0, sizeof(vhstore));
                for (struct cmsghdr *c = CMSG_FIRSTHDR(&mh); c;
                     c = CMSG_NXTHDR(&mh, c)) {
                    if (c->cmsg_level == SOL_PACKET &&
                        c->cmsg_type == PACKET_AUXDATA &&
                        c->cmsg_len >= CMSG_LEN(sizeof(struct tpacket_auxdata))) {
                        struct tpacket_auxdata aux;
                        memcpy(&aux, CMSG_DATA(c), sizeof(aux));
                        if (aux.tp_status & TP_STATUS_OUTGOING) aux_outgoing = 1;
                        aux_mac_off = aux.tp_mac;
                        if (aux.tp_status & TP_STATUS_CSUMNOTREADY) meta.csumnotready = 1;
                        if (aux.tp_status & TP_STATUS_CSUM_VALID) meta.csum_valid = 1;
                        if (aux.tp_status & TP_STATUS_VLAN_VALID) meta.vlan_valid = 1;
                        if (aux.tp_status & TP_STATUS_VLAN_TPID_VALID) meta.vlan_tpid_valid = 1;
                        meta.vlan_tci = aux.tp_vlan_tci;
                        meta.vlan_tpid = aux.tp_vlan_tpid;
                    }
                }
                if (aux_outgoing) st.auxdata_outgoing++;
                if (meta.csumnotready) st.aux_csumnotready++;
                if (meta.csum_valid) st.aux_csum_valid++;
                if (meta.vlan_valid) st.aux_vlan_valid++;
                if (meta.vlan_tpid_valid) st.aux_vlan_tpid_valid++;

                /* The packet type the kernel actually assigned to this frame is
                 * the direction. Everything else is a guess about a guess. */
                int outgoing = 0;
                switch (from.sll_pkttype) {
                case PACKET_HOST:      st.pkttype_host++; break;
                case PACKET_BROADCAST: st.pkttype_broadcast++; break;
                case PACKET_MULTICAST: st.pkttype_multicast++; break;
                case PACKET_OTHERHOST: st.pkttype_otherhost++; break;
                case PACKET_OUTGOING:  st.pkttype_outgoing++; outgoing = 1; break;
                default:               st.pkttype_unknown++; break;
                }
                if (outgoing) {
                    /* Rejected before any forwarding policy runs, so a frame we
                     * emitted can never be flooded, learned from, or counted as
                     * inbound traffic. This is the whole defence against a bridge
                     * amplifying itself. */
                    st.self_echo++;
                    continue;
                }

                if (cfg.ports[i].vnet_rx && n > (ssize_t)sizeof(vhstore)) {
                    vh = &vhstore;
                    memcpy(vh, buf, sizeof(*vh));
                    /* tp_mac is authoritative when the kernel supplies it; the
                     * header length is the fallback. */
                    off = aux_mac_off ? aux_mac_off : sizeof(*vh);
                    if (off != sizeof(*vh) || (size_t)off >= (size_t)n) {
                        vh = NULL;
                        off = 0;
                    }
                }
                if (meta.csumnotready) st.csumnotready_seen++;
                if (vh && (vh->flags & VIRTIO_NET_HDR_F_NEEDS_CSUM)) st.deferred_in++;
                const uint8_t *data = buf + off;
                ssize_t ndata = n - (ssize_t)off;

                if (cfg.sample > 0 && (st.rx % (uint64_t)cfg.sample) == 0) {
                    char sm[32], dm[32];
                    if (ndata >= (ssize_t)BR_ETH_HDR_LEN) {
                        br_mac_format(data + BR_MACLEN, sm, sizeof(sm));
                        br_mac_format(data, dm, sizeof(dm));
                    } else {
                        snprintf(sm, sizeof(sm), "-");
                        snprintf(dm, sizeof(dm), "-");
                    }
                    char et[16];
                    if (ndata >= (ssize_t)BR_ETH_HDR_LEN)
                        br_ethertype_format(br_ethertype(data, (size_t)ndata), et, sizeof(et));
                    else
                        snprintf(et, sizeof(et), "-");
                    br_log_msg("sample: in=%s pkttype=%u len=%zd ethtype=%s "
                               "csumnotready=%d csumvalid=%d vlanvalid=%d "
                               "vlan_tci=0x%04x vlan_tpid=0x%04x src=%s dst=%s",
                               cfg.ports[i].name, from.sll_pkttype, ndata, et,
                               meta.csumnotready, meta.csum_valid, meta.vlan_valid,
                               meta.vlan_tci, meta.vlan_tpid, sm, dm);
                }

                cfg.ports[i].rx++;
                st.rx++;

                struct br_decision d;
                br_fwd_decide(data, (size_t)ndata, i, cfg.nports, &cam, now, &meta, &d);
                if (d.not_learned) st.source_not_learned++;
                if (d.moved)
                    br_log_msg("cam: an address moved between ports; this is what a "
                               "loop in the segment looks like. Not repairing it: "
                               "the topology is required to be a tree.");
                if (d.evicted)
                    br_log_msg("cam: table full, evicted a least recently seen address");

                switch (d.action) {
                case BR_DROP:
                    br_count_reason(&st, d.reason);
                    break;
                case BR_UNICAST: {
                    int deferred = vh && (vh->flags & VIRTIO_NET_HDR_F_NEEDS_CSUM);
                    int rc = br_send_frame(&cfg.ports[d.port], data, (size_t)ndata, vh);
                    if (rc == 0) {
                        cfg.ports[d.port].tx++;
                        st.forwarded++;
                        st.unicast++;
                        if (deferred) st.deferred_carried++;
                    } else if (rc == -2) {
                        st.deferred_refused++;
                        st.dropped++;
                    } else {
                        cfg.ports[d.port].tx_failed++;
                        br_count_reason(&st, BR_R_TX_FAILED);
                    }
                    break;
                }
                case BR_FLOOD:
                    emit(&cfg, i, data, (size_t)ndata, &st, vh);
                    break;
                }
            }
        }
    }

    br_log_msg("%s: shutting down", cfg.svcname);
    dump_stats(&cfg, &st, &cam);
    close_all(&cfg);
    br_cam_free(&cam);
    return 0;
}

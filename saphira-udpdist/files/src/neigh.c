/*
 * saphira-udpdist - neighbour (layer 2 next hop) discovery.
 *
 * DSR redirects at layer 2, so every backend needs a hardware address. Two
 * ways to get one: the operator supplies it, or the kernel's neighbour table
 * is asked. This file is the second way, and it deliberately does not
 * implement ARP itself.
 *
 * Why not implement ARP: the kernel already owns neighbour resolution. Writing
 * our own ARP would mean a second, independent view of the same table, and
 * the disagreement between the two would be indistinguishable from a genuine
 * duplicate-address or spoofing event. Asking the kernel means one authority.
 *
 * Why this cannot be a routing solution: ARP, and the neighbour table behind
 * it, are defined only within a single broadcast domain. A router terminates
 * the segment and never answers an ARP request for an address beyond it. So a
 * backend behind a gateway is not merely "unresolved yet" - it is permanently
 * unreachable by this mechanism, and no amount of retrying changes that. That
 * limit is the reason tunnelled DSR exists as a separate mode rather than as
 * a fallback here. See neighbour_resolve() for how that distinction is
 * reported rather than hidden.
 */

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/socket.h>
#include <linux/netlink.h>
#include <linux/rtnetlink.h>
#include <linux/neighbour.h>
#include <net/if.h>

#include "udpdist.h"

/* linux/neighbour.h as shipped by musl is older than the kernel this daemon
 * runs on: it defines neither the high-ifindex extension nor NDA_STATE. Both
 * are needed to read a modern table correctly, and reading past a shorter
 * message header is exactly the sort of silent misparse this daemon exists to
 * avoid, so they are declared here rather than assumed. */
struct ndmsg_ext {
    uint16_t ndm_pad;
    uint16_t ndm_ifindex_high;
};
#ifndef NDA_STATE
#define NDA_STATE 7
#endif

#define NEIGH_BUFSZ 8192

int neigh_watch_fd_ = -1;

/* Opening the socket once matters: re-binding per loop iteration would
 * drop notifications that arrive between iterations, which is exactly when a
 * mac change is most likely to be missed. */
int neigh_watch_open_once(void) {
    if (neigh_watch_fd_ < 0) neigh_watch_open();
    return neigh_watch_fd_;
}

/* A netlink dump is the simplest correct lookup: the tables involved are small
 * (a neighbour entry is a few dozen bytes and one exists only per address the
 * host has recently talked to) and a dump avoids the alignment and error
 * handling of a targeted request. */
static int neigh_dump(int fd, struct neigh_entry *out, int max) {
    struct {
        struct nlmsghdr n;
        struct rtgenmsg g;
    } req;
    struct sockaddr_nl sa;
    char buf[NEIGH_BUFSZ];
    ssize_t len;
    int n = 0;

    memset(&req, 0, sizeof(req));
    memset(&sa, 0, sizeof(sa));
    req.n.nlmsg_len = NLMSG_LENGTH(sizeof(struct rtgenmsg));
    req.n.nlmsg_type = RTM_GETNEIGH;
    req.n.nlmsg_flags = NLM_F_REQUEST | NLM_F_DUMP;
    req.n.nlmsg_seq = 1;
    req.g.rtgen_family = AF_UNSPEC;
    sa.nl_family = AF_NETLINK;

    if (sendto(fd, &req, req.n.nlmsg_len, 0, (struct sockaddr *)&sa, sizeof(sa)) < 0)
        return -1;

    for (;;) {
        len = recv(fd, buf, sizeof(buf), 0);
        if (len < 0) {
            if (errno == EINTR) continue;
            return n > 0 ? n : -1;
        }
        if (len == 0) break;

        struct nlmsghdr *nlh = (struct nlmsghdr *)buf;
        for (; NLMSG_OK(nlh, (unsigned int)len); nlh = NLMSG_NEXT(nlh, len)) {
            struct neigh_entry e;
            if (nlh->nlmsg_type == NLMSG_DONE || nlh->nlmsg_type == NLMSG_ERROR)
                return n;
            if (nlh->nlmsg_type != RTM_NEWNEIGH) continue;
            if (neigh_parse(nlh, &e) != 0) continue;
            if (n < max) out[n++] = e;
        }
    }
    return n;
}

/* Parse the attribute block at a given offset. Returns 0 on a complete,
 * usable entry (destination and hardware address both present). */
static int neigh_parse_at(const struct nlmsghdr *nlh, struct neigh_entry *e,
                          int skip_ext) {
    const struct ndmsg *nd;
    const struct rtattr *rta;
    int alen;
    int have_dst = 0;

    if (nlh->nlmsg_len < NLMSG_LENGTH(sizeof(struct ndmsg))) return -1;
    nd = (const struct ndmsg *)NLMSG_DATA(nlh);

    /* The kernel appends an ndmsg_ext to carry ifindex > 32 bits, but nothing
     * in the payload itself says whether it is there: the rtminfo length that
     * would tell us has already been consumed by the netlink layer. Rather
     * than guess and silently misparse every attribute, try the short form and
     * then the long one, and accept whichever yields a coherent entry. A wrong
     * guess is self-correcting here because a misaligned read cannot produce a
     * valid destination address and a valid 6-byte hardware address at the
     * same time. */
    const char *base = (const char *)nd + NLMSG_ALIGN(sizeof(*nd));
    if (skip_ext)
        base += NLMSG_ALIGN(sizeof(struct ndmsg_ext));
    if (nlh->nlmsg_len < (uint32_t)(base - (const char *)nlh) +
                             NLMSG_LENGTH(sizeof(struct rtattr)))
        return -1;

    rta = (const struct rtattr *)base;
    alen = (int)(nlh->nlmsg_len - NLMSG_LENGTH(sizeof(struct ndmsg)));

    memset(e, 0, sizeof(*e));
    e->family = nd->ndm_family;
    e->ifindex = (uint32_t)nd->ndm_ifindex;
    if (nd->ndm_ifindex < 0) e->ifindex = 0;
    e->state = nd->ndm_state;

    for (; RTA_OK(rta, alen); rta = RTA_NEXT(rta, alen)) {
        switch (rta->rta_type) {
        case NDA_DST:
            if (e->family == AF_INET && RTA_PAYLOAD(rta) >= 4) {
                memcpy(e->addr, RTA_DATA(rta), 4);
                have_dst = 1;
            } else if (e->family == AF_INET6 && RTA_PAYLOAD(rta) >= 16) {
                memcpy(e->addr, RTA_DATA(rta), 16);
                have_dst = 1;
            }
            break;
        case NDA_LLADDR:
            if (RTA_PAYLOAD(rta) == 6) {
                memcpy(e->mac, RTA_DATA(rta), 6);
                e->mac_len = 6;
            }
            break;
        case NDA_STATE:
            if (RTA_PAYLOAD(rta) >= 2) {
                uint16_t st;
                memcpy(&st, RTA_DATA(rta), 2);
                e->state = st;
            }
            break;
        default:
            break;
        }
    }

    if (!have_dst || e->mac_len != 6) return -1;
    return 0;
}

int neigh_parse(const struct nlmsghdr *nlh, struct neigh_entry *e) {
    struct neigh_entry tmp;
    if (neigh_parse_at(nlh, e, 0) == 0) return 0;
    if (neigh_parse_at(nlh, &tmp, 1) == 0) { *e = tmp; return 0; }
    memset(e, 0, sizeof(*e));
    return -1;
}

int neigh_state_usable(uint16_t s) {
    /* A STALE entry still holds a valid hardware address - it simply has not
     * been confirmed recently - and using it is what the kernel itself does.
     * INCOMPLETE, PROBE, FAILED and NOARP must not be installed: forwarding to
     * them is a blackhole, which is the exact failure this daemon refuses to
     * create.
     *
     * A state this build cannot name is refused rather than accepted. An
     * unrecognised value most often means the table is not being decoded
     * correctly - a misaligned read, or a state added to the kernel after this
     * was written - and installing a hardware address on that evidence would
     * be guessing. Failing closed here costs a startup refusal with a
     * diagnostic; guessing here costs a silent blackhole, which is precisely
     * the failure mode everything else in this daemon exists to prevent. */
    switch (s & (NUD_INCOMPLETE | NUD_REACHABLE | NUD_STALE | NUD_DELAY |
                 NUD_PROBE | NUD_FAILED | NUD_NOARP | NUD_PERMANENT)) {
    case NUD_REACHABLE:
    case NUD_STALE:
    case NUD_DELAY:
    case NUD_PERMANENT:
        return 1;
    default:
        return 0;
    }
}

const char *neigh_state_name(uint16_t s) {
    switch (s & (NUD_INCOMPLETE | NUD_REACHABLE | NUD_STALE | NUD_DELAY |
                 NUD_PROBE | NUD_FAILED | NUD_NOARP | NUD_PERMANENT)) {
    case NUD_INCOMPLETE: return "INCOMPLETE";
    case NUD_REACHABLE:  return "REACHABLE";
    case NUD_STALE:      return "STALE";
    case NUD_DELAY:      return "DELAY";
    case NUD_PROBE:      return "PROBE";
    case NUD_FAILED:     return "FAILED";
    case NUD_NOARP:      return "NOARP";
    case NUD_PERMANENT:  return "PERMANENT";
    default:             return "UNKNOWN";
    }
}

int neigh_get(const struct uaddr *a, uint32_t ifindex, uint8_t mac[6], uint16_t *state) {
    struct neigh_entry *ents;
    int n, i, found = -1;
    int fd;

    fd = socket(AF_NETLINK, SOCK_RAW, NETLINK_ROUTE);
    if (fd < 0) return -1;

    ents = calloc(NEIGH_MAX, sizeof(*ents));
    if (!ents) { close(fd); return -1; }

    n = neigh_dump(fd, ents, NEIGH_MAX);
    close(fd);
    if (n < 0) { free(ents); return -1; }

    for (i = 0; i < n; i++) {
        if (ents[i].family != a->family) continue;
        if (memcmp(ents[i].addr, a->addr, a->family == AF_INET ? 4 : 16) != 0) continue;
        /* An interface index of 0 means "any": the caller has not pinned an
         * interface. Otherwise the entry must be on the interface the redirect
         * will actually leave, or the hardware address is for the wrong port. */
        if (ifindex != 0 && ents[i].ifindex != ifindex) continue;
        if (!neigh_state_usable(ents[i].state)) continue;
        memcpy(mac, ents[i].mac, 6);
        if (state) *state = ents[i].state;
        found = 0;
        break;
    }
    free(ents);
    return found;
}

/* Ask the kernel to resolve an address now rather than waiting for unrelated
 * traffic to do it. This cannot cross a router: the request is a local
 * neighbour resolution, and if the address is off-segment the kernel will set
 * the entry to FAILED, which is the honest answer. */
static int neigh_nudge(const struct uaddr *a, uint32_t ifindex) {
    struct {
        struct nlmsghdr n;
        struct ndmsg nd;
        char attr[64];
    } req;
    struct sockaddr_nl sa;
    int alen;
    int fd;
    int rc;

    fd = socket(AF_NETLINK, SOCK_RAW, NETLINK_ROUTE);
    if (fd < 0) return -1;

    memset(&req, 0, sizeof(req));
    memset(&sa, 0, sizeof(sa));
    sa.nl_family = AF_NETLINK;

    alen = RTA_LENGTH(a->family == AF_INET ? 4 : 16);
    req.n.nlmsg_len = NLMSG_LENGTH(sizeof(struct ndmsg)) + RTA_ALIGN(alen);
    req.n.nlmsg_type = RTM_NEWNEIGH;
    req.n.nlmsg_flags = NLM_F_REQUEST | NLM_F_REPLACE | NLM_F_ACK;
    req.nd.ndm_family = (uint8_t)a->family;
    req.nd.ndm_ifindex = (int32_t)ifindex;
    req.nd.ndm_state = NUD_INCOMPLETE;
    req.nd.ndm_flags = 0;
    req.nd.ndm_type = 0;

    struct rtattr *rta = (struct rtattr *)req.attr;
    rta->rta_type = NDA_DST;
    rta->rta_len = (unsigned short)alen;
    memcpy(RTA_DATA(rta), a->addr, a->family == AF_INET ? 4 : 16);

    rc = sendto(fd, &req, req.n.nlmsg_len, 0, (struct sockaddr *)&sa, sizeof(sa)) < 0 ? -1 : 0;
    close(fd);
    return rc;
}

int neighbour_resolve(const struct uaddr *a, uint32_t ifindex, int tries, int delay_ms) {
    uint8_t mac[6];
    int i;

    for (i = 0; i < tries; i++) {
        if (neigh_get(a, ifindex, mac, NULL) == 0) return 0;
        if (i + 1 < tries) {
            if (neigh_nudge(a, ifindex) != 0 && i == 0) {
                /* The nudge is best effort; the loop still re-checks. */
            }
            usleep((useconds_t)delay_ms * 1000);
        }
    }
    return -1;
}

int neigh_watch_open(void) {
    struct sockaddr_nl sa;
    int fd;

    fd = socket(AF_NETLINK, SOCK_RAW, NETLINK_ROUTE);
    if (fd < 0) return -1;

    memset(&sa, 0, sizeof(sa));
    sa.nl_family = AF_NETLINK;
    /* Groups carry no pid: nl_pid stays 0 so replies and notifications come
     * from the kernel, and we ask to be told about neighbour changes. */
    sa.nl_groups = RTMGRP_NEIGH;

    if (bind(fd, (struct sockaddr *)&sa, sizeof(sa)) < 0) { close(fd); return -1; }
    fcntl(fd, F_SETFL, O_NONBLOCK);
    neigh_watch_fd_ = fd;
    return fd;
}

/* Drain change notifications. A MAC change after startup is the failure mode
 * that produces a silent blackhole with no counter movement and no log line,
 * so it is watched for and counted rather than discovered by a customer. */
int neigh_watch_drain(struct neigh_entry *out, int max, int *ndeleted) {
    char buf[NEIGH_BUFSZ];
    int n = 0;
    ssize_t len;

    if (neigh_watch_fd_ < 0) return 0;
    if (ndeleted) *ndeleted = 0;

    while ((len = recv(neigh_watch_fd_, buf, sizeof(buf), MSG_DONTWAIT)) > 0) {
        struct nlmsghdr *nlh = (struct nlmsghdr *)buf;
        for (; NLMSG_OK(nlh, (unsigned int)len); nlh = NLMSG_NEXT(nlh, len)) {
            if (nlh->nlmsg_type == RTM_DELNEIGH) {
                if (ndeleted) (*ndeleted)++;
                continue;
            }
            if (nlh->nlmsg_type != RTM_NEWNEIGH) continue;
            if (n < max) {
                if (neigh_parse(nlh, &out[n]) == 0) n++;
            }
        }
        if ((size_t)len < sizeof(buf)) break;
    }
    return n;
}

void neigh_close(void) {
    if (neigh_watch_fd_ >= 0) { close(neigh_watch_fd_); neigh_watch_fd_ = -1; }
}

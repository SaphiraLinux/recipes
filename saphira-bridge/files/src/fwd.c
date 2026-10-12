/*
 * saphira-bridge - the forwarding decision.
 * BUSL-1.1, see LICENSE.
 *
 * This file is the product. Everything else is transport: getting frames in,
 * and putting them out the port this function names. The decision is separated
 * from the I/O precisely so the policy can be tested exhaustively with no
 * privileges, no interfaces and no kernel involvement, which is the only way
 * to be confident about the cases that matter - the ones where a bridge
 * either loops a frame or silently loses it.
 */
#include <string.h>

#include "bridge.h"

const char *br_action_name(enum br_action a) {
    switch (a) {
    case BR_DROP: return "drop";
    case BR_UNICAST: return "unicast";
    case BR_FLOOD: return "flood";
    }
    return "unknown";
}

const char *br_reason_name(enum br_reason r) {
    switch (r) {
    case BR_R_NONE: return "none";
    case BR_R_TOO_SHORT: return "too-short";
    case BR_R_VLAN_TAGGED: return "vlan-tagged";
    case BR_R_RESERVED: return "reserved-multicast";
    case BR_R_TX_FAILED: return "tx-failed";
    case BR_R_NO_EGRESS: return "no-egress";
    }
    return "unknown";
}

int br_meta_has_vlan(const struct br_meta *m) {
    return m != NULL && (m->vlan_valid || m->vlan_tpid_valid);
}

int br_fwd_decide(const uint8_t *frame, size_t len, int in_port, int nports,
                  struct br_cam *cam, time_t now, const struct br_meta *meta,
                  struct br_decision *d) {
    memset(d, 0, sizeof(*d));
    d->action = BR_DROP;
    d->port = -1;
    d->reason = BR_R_NONE;

    if (in_port < 0 || in_port >= nports) {
        d->reason = BR_R_TOO_SHORT;
        return -1;
    }
    if (len < BR_ETH_HDR_LEN) {
        d->reason = BR_R_TOO_SHORT;
        return -1;
    }

    const uint8_t *dst = frame;
    const uint8_t *src = frame + BR_MACLEN;

    /* Order matters and is not arbitrary. A tagged frame must be refused
     * before anything is learnt from it, because its source address is still
     * correct but its destination and ethertype are not where they appear to
     * be, and learning a destination from it would poison the table. */
    /* A tag can be delivered two ways: present in the bytes, or reported by the
     * kernel in the auxdata after being stripped from the buffer. Measured on
     * this host: a well-formed 802.1Q frame arrives four bytes short with the
     * inner ethertype at offset 12, so reading only the bytes would forward a
     * tagged frame as if it were untagged. Both signals are accepted. */
    if (br_is_vlan_tagged(frame, len) || br_meta_has_vlan(meta)) {
        d->reason = BR_R_VLAN_TAGGED;
        return 0;
    }
    if (br_is_reserved(dst)) {
        d->reason = BR_R_RESERVED;
        return 0;
    }

    /* Learn from unicast sources only. A frame whose source address is a
     * group address is claiming to speak for a group, and a table that takes
     * its word for it can be fed a forged mapping for a legitimate host. The
     * frame still forwards - refusing it would be a filter, not a bridge - but
     * nothing is learnt from it. */
    if (!br_is_multicast(src)) {
        int moved = 0, evicted = 0;
        if (br_cam_learn(cam, src, in_port, now, &moved, &evicted) == 0) {
            d->learned = 1;
            d->moved = moved;
            d->evicted = evicted;
        }
    } else {
        /* Recorded separately from the drop reason: the frame is forwarded,
         * only the learning is refused, and conflating the two would let a
         * forwarded frame clear the counter that exists to notice the refusal. */
        d->not_learned = 1;
    }

    if (br_is_multicast(dst)) {
        /* Broadcast and multicast are flooded, never unicast-forwarded. */
        d->action = BR_FLOOD;
        d->reason = BR_R_NONE;
        return 0;
    }

    int port = -1;
    if (br_cam_lookup(cam, dst, &port) == 0 && port >= 0 && port != in_port) {
        d->action = BR_UNICAST;
        d->port = port;
        d->reason = BR_R_NONE;
        return 0;
    }

    /* Either the destination is unknown, or it is known to live on the port the
     * frame just arrived from. The second case is a frame addressed to a host
     * that is talking to itself, and it is also what a loop looks like from
     * here. Sending it back out the ingress port would multiply it, so it is
     * dropped and counted rather than reflected. */
    if (port == in_port) {
        d->action = BR_DROP;
        d->reason = BR_R_NO_EGRESS;
        return 0;
    }

    /* Unknown destination: flood. Dropping instead would break first contact
     * invisibly, and flooding is what a bridge is for. Every flood is counted
     * so that a segment which is flooding far more than it should is visible
     * rather than merely slow. */
    d->action = BR_FLOOD;
    d->reason = BR_R_NONE;
    return 0;
}

/* saphira-bridge rootless unit tests. BUSL-1.1, see LICENSE
 *
 * These exercise the policy core with no privileges, no interfaces and no
 * kernel involvement. If a forwarding or CAM rule is wrong, it is wrong here
 * first, which is the only place a test can prove it exhaustively.
 */
#include "../src/bridge.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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
        printf("  FAIL [%s] %s (got %d, want %d)\n", group, what, got, want);
    }
}

static const uint8_t M1[6] = {0x02, 0, 0, 0, 0, 1};
static const uint8_t M2[6] = {0x02, 0, 0, 0, 0, 2};
static const uint8_t M3[6] = {0x02, 0, 0, 0, 0, 3};
static const uint8_t BC[6] = {0xff, 0xff, 0xff, 0xff, 0xff, 0xff};
static const uint8_t MC[6] = {0x33, 0x33, 0, 0, 0, 1};

static void t_mac(void) {
    uint8_t m[6];
    char buf[32];

    group = "addresses";
    okrc(br_mac_parse("52:54:00:12:34:56", m), 0, "a full address parses");
    ok(m[0] == 0x52 && m[5] == 0x56, "the octets land in order");
    okrc(br_mac_parse("52:54:00:12:34", m), -1, "five octets are refused");
    okrc(br_mac_parse("52:54:00:12:34:56:78", m), -1, "seven octets are refused");
    okrc(br_mac_parse("zz:54:00:12:34:56", m), -1, "non-hex is refused");
    okrc(br_mac_parse("", m), -1, "the empty string is refused");

    br_mac_format(m, buf, sizeof(buf));
    ok(strcmp(buf, "52:54:00:12:34:56") == 0, "format round-trips");
}

static void t_classify(void) {
    group = "classification";
    ok(br_is_broadcast(BC), "ff:ff:ff:ff:ff:ff is broadcast");
    ok(!br_is_broadcast(M1), "a unicast address is not broadcast");
    ok(br_is_multicast(MC), "33:33:00:00:00:01 is multicast");
    ok(br_is_multicast(BC), "broadcast is a group address");
    ok(!br_is_multicast(M1), "a unicast address is not multicast");

    /* 802.1D reserves 01:80:C2:00:00:00..0f for protocol traffic. A bridge that
     * learns from or floods these as ordinary data can be steered by another
     * bridge's control frames. */
    for (int i = 0; i <= 0x0f; i++) {
        uint8_t r[6] = {0x01, 0x80, 0xc2, 0x00, 0x00, (uint8_t)i};
        char what[64];
        snprintf(what, sizeof(what), "01:80:c2:00:00:%02x is reserved", i);
        ok(br_is_reserved(r), what);
    }
    {
        uint8_t edge[6] = {0x01, 0x80, 0xc2, 0x00, 0x00, 0x10};
        ok(!br_is_reserved(edge), "01:80:c2:00:00:10 is just past the reserved block");
        uint8_t other[6] = {0x01, 0x80, 0xc2, 0x00, 0x01, 0x00};
        ok(!br_is_reserved(other), "01:80:c2:00:01:00 is outside the block");
    }
}

static void t_eth(void) {
    uint8_t f[64];
    char buf[16];

    group = "ethernet";
    memset(f, 0, sizeof(f));
    memcpy(f, M1, 6);
    memcpy(f + 6, M2, 6);
    f[12] = 0x08;
    f[13] = 0x00; /* ARP */
    okrc((int)br_ethertype(f, sizeof(f)), 0x0800, "IPv4 ethertype is read big-endian");
    ok(!br_is_vlan_tagged(f, sizeof(f)), "an untagged frame is not tagged");

    f[12] = 0x81;
    f[13] = 0x00;
    ok(br_is_vlan_tagged(f, sizeof(f)), "802.1Q is recognised");
    f[12] = 0x88;
    f[13] = 0xa8;
    ok(br_is_vlan_tagged(f, sizeof(f)), "802.1ad is recognised");
    f[12] = 0x91;
    f[13] = 0x00;
    ok(br_is_vlan_tagged(f, sizeof(f)), "the legacy QinQ tag is recognised too");
    f[12] = 0x08;
    f[13] = 0x06;
    ok(!br_is_vlan_tagged(f, sizeof(f)), "ARP is not a tag");
    okrc((int)br_ethertype(f, 4), 0, "a truncated frame has no ethertype");

    br_ethertype_format(0x0800, buf, sizeof(buf));
    ok(strcmp(buf, "0x0800") == 0, "ethertype formats for a log line");
}

static void t_cam(void) {
    struct br_cam c;
    int port = -1, moved = 0, evicted = 0;
    uint8_t m[6];
    char sbuf[32];

    group = "cam";
    okrc(br_cam_init(&c, 4, 300), -1, "too small a table is refused");
    okrc(br_cam_init(&c, BR_CAM_MAX + 1, 300), -1, "an oversized table is refused");
    okrc(br_cam_init(&c, 64, 0), -1, "a zero age is refused");
    okrc(br_cam_init(&c, 64, 300), 0, "a sane table initialises");

    okrc(br_cam_count(&c), 0, "a new table is empty");
    okrc(br_cam_lookup(&c, M1, &port), -1, "an unknown address is not found");
    okrc(br_cam_learn(&c, M1, 1, 1000, &moved, &evicted), 0, "a new address is learnt");
    okrc(br_cam_count(&c), 1, "learning grew the table");
    okrc(br_cam_lookup(&c, M1, &port), 0, "the address is now found");
    okrc(port, 1, "on the port it arrived from");
    okrc(moved, 0, "first sight of an address is not a move");

    /* the same address on the same port is just traffic */
    okrc(br_cam_learn(&c, M1, 1, 1001, &moved, &evicted), 0, "re-learning is fine");
    okrc(moved, 0, "staying on a port is not a move");
    okrc(br_cam_count(&c), 1, "re-learning did not grow the table");
    okrc(c.learnt, 1, "only genuinely new addresses count as learnt");

    /* moving is the cheap loop signal, and must be visible */
    okrc(br_cam_learn(&c, M1, 2, 1002, &moved, &evicted), 0, "an address may move");
    okrc(moved, 1, "a move is reported");
    okrc(c.moved, 1, "a move is counted");
    okrc(br_cam_lookup(&c, M1, &port), 0, "the address is still found");
    okrc(port, 2, "on its new port");

    group = "cam ageing";
    okrc(br_cam_learn(&c, M2, 0, 1000, &moved, &evicted), 0, "second address learnt");
    okrc(br_cam_count(&c), 2, "two entries present");
    okrc(br_cam_age(&c, 1000 + 299), 0, "nothing expires just before the age");
    okrc(br_cam_count(&c), 2, "and the table is unchanged");
    /* M1 was last seen at 1002, M2 at 1000 */
    okrc(br_cam_age(&c, 1000 + 300), 1, "the stale entry expires at the age");
    okrc(c.expired, 1, "expiry is counted");
    okrc(br_cam_count(&c), 1, "the expired entry is gone");
    okrc(br_cam_lookup(&c, M1, &port), 0, "the recently seen address survives");
    okrc(br_cam_lookup(&c, M2, &port), -1, "the stale address is gone");

    group = "cam bound";
    /* Branch one: a full table of live entries must give up the least recently
     * seen one, and must never give up the most recent. */
    br_cam_free(&c);
    okrc(br_cam_init(&c, 8, 3000), 0, "a small table initialises");
    for (int i = 1; i <= 8; i++) {
        snprintf(sbuf, sizeof(sbuf), "02:00:00:00:00:%02x", i);
        br_mac_parse(sbuf, m);
        okrc(br_cam_learn(&c, m, 0, 1000, &moved, &evicted), 0, "fill the table");
    }
    okrc(br_cam_count(&c), 8, "the table is at its bound");
    snprintf(sbuf, sizeof(sbuf), "02:00:00:00:00:01");
    br_mac_parse(sbuf, m);
    br_cam_learn(&c, m, 1, 3000, &moved, &evicted);   /* the newest entry */
    snprintf(sbuf, sizeof(sbuf), "02:00:00:00:00:09");
    br_mac_parse(sbuf, m);
    okrc(br_cam_learn(&c, m, 2, 1000, &moved, &evicted), 0,
         "an address past the bound is still accepted");
    okrc(evicted, 1, "by evicting something");
    okrc(c.evicted, 1, "and the eviction is counted");
    okrc(br_cam_count(&c), 8, "the bound is still the bound, not exceeded");
    okrc(br_cam_lookup(&c, m, &port), 0, "the arriving address is present");
    snprintf(sbuf, sizeof(sbuf), "02:00:00:00:00:01");
    br_mac_parse(sbuf, m);
    okrc(br_cam_lookup(&c, m, &port), 0,
         "the most recently seen entry was not the one evicted");

    /* Branch two: when the table is full of entries that are already past
     * their idle age, expiry must make room before any live entry is given
     * up. A full table is not by itself a reason to evict a live host. */
    br_cam_free(&c);
    okrc(br_cam_init(&c, 8, 10), 0, "a short-age table initialises");
    for (int i = 1; i <= 8; i++) {
        snprintf(sbuf, sizeof(sbuf), "02:00:00:00:00:%02x", i);
        br_mac_parse(sbuf, m);
        br_cam_learn(&c, m, 0, 1000, &moved, &evicted);
    }
    snprintf(sbuf, sizeof(sbuf), "02:00:00:00:00:01");
    br_mac_parse(sbuf, m);
    br_cam_learn(&c, m, 1, 5000, &moved, &evicted);  /* keep this one alive */
    snprintf(sbuf, sizeof(sbuf), "02:00:00:00:00:09");
    br_mac_parse(sbuf, m);
    okrc(br_cam_learn(&c, m, 2, 5000, &moved, &evicted), 0,
         "a new address arrives into a full table of stale entries");
    okrc(evicted, 0,
         "and nothing live was evicted: expiry made the room instead");
    /* Seven stale entries were reclaimed and the arriving address took one, so
     * the count is legitimately 2 rather than 8. The property that matters is
     * that it never rose above the bound. */
    okrc(br_cam_count(&c), 2,
         "expiry reclaimed the seven stale slots and the arrival took one");
    okrc(c.expired, 7, "the reclaimed entries are counted as expired, not evicted");
    snprintf(sbuf, sizeof(sbuf), "02:00:00:00:00:09");
    br_mac_parse(sbuf, m);
    okrc(br_cam_lookup(&c, m, &port), 0, "the arriving address is present");
    snprintf(sbuf, sizeof(sbuf), "02:00:00:00:00:01");
    br_mac_parse(sbuf, m);
    okrc(br_cam_lookup(&c, m, &port), 0, "the one live entry survived");
    br_cam_free(&c);
}

static void mkframe(uint8_t *f, const uint8_t dst[6], const uint8_t src[6],
                    unsigned ethertype) {
    memset(f, 0, 64);
    memcpy(f, dst, 6);
    memcpy(f + 6, src, 6);
    f[12] = (uint8_t)(ethertype >> 8);
    f[13] = (uint8_t)(ethertype & 0xff);
}

static void t_fwd(void) {
    struct br_cam c;
    struct br_decision d;
    uint8_t f[64];
    int moved = 0, evicted = 0;

    group = "forwarding";
    br_cam_init(&c, 64, 300);

    /* a frame that cannot even hold a header */
    okrc(br_fwd_decide(f, 8, 0, 2, &c, 1000, NULL, &d), -1, "a runt is rejected");
    okrc(d.reason, BR_R_TOO_SHORT, "and the reason is too-short");

    /* learning, then known-unicast delivery */
    mkframe(f, M2, M1, 0x0800);
    okrc(br_fwd_decide(f, 64, 0, 2, &c, 1000, NULL, &d), 0, "a first frame is accepted");
    okrc(d.action, BR_FLOOD, "its unknown destination is flooded");
    okrc(d.learned, 1, "and its source is learnt");
    br_cam_learn(&c, M2, 1, 1000, &moved, &evicted);

    mkframe(f, M2, M1, 0x0800);
    okrc(br_fwd_decide(f, 64, 0, 2, &c, 1000, NULL, &d), 0, "a second frame is accepted");
    okrc(d.action, BR_UNICAST, "a known destination is not flooded");
    okrc(d.port, 1, "it goes to the learned port");
    okrc(d.learned, 1, "the source is refreshed");

    /* broadcast and multicast flood, and are never unicast-forwarded */
    mkframe(f, BC, M1, 0x0806);
    br_fwd_decide(f, 64, 0, 2, &c, 1000, NULL, &d);
    okrc(d.action, BR_FLOOD, "broadcast floods");
    mkframe(f, MC, M1, 0x0800);
    br_fwd_decide(f, 64, 0, 2, &c, 1000, NULL, &d);
    okrc(d.action, BR_FLOOD, "multicast floods without snooping");

    /* a group address as a source teaches nothing */
    mkframe(f, BC, MC, 0x0806);
    int before = br_cam_count(&c);
    br_fwd_decide(f, 64, 0, 2, &c, 1000, NULL, &d);
    okrc(br_cam_count(&c), before,
         "a multicast source cannot poison the table");
    okrc(d.action, BR_FLOOD, "but the frame still forwards");
    okrc(d.not_learned, 1, "and the refusal to learn is recorded on its own");
    okrc(d.reason, BR_R_NONE,
         "a forwarded frame carries no drop reason at all");

    /* a frame addressed to the host that sent it: dropping beats reflecting,
     * because reflecting it back out the ingress port is how a loop multiplies
     * itself */
    mkframe(f, M1, M1, 0x0800);
    br_fwd_decide(f, 64, 0, 2, &c, 1000, NULL, &d);
    okrc(d.action, BR_DROP, "a self-addressed frame is not sent back");
    okrc(d.reason, BR_R_NO_EGRESS, "and the reason is no-egress");

    /* 802.1D reserved traffic is neither learnt nor forwarded */
    {
        uint8_t r[6] = {0x01, 0x80, 0xc2, 0x00, 0x00, 0x00};
        int cnt = br_cam_count(&c);
        mkframe(f, r, M3, 0x88cc);
        br_fwd_decide(f, 64, 0, 2, &c, 1000, NULL, &d);
        okrc(d.action, BR_DROP, "reserved control traffic is dropped");
        okrc(d.reason, BR_R_RESERVED, "with the reserved reason");
        okrc(br_cam_count(&c), cnt, "and nothing is learnt from it");
        br_fwd_decide(f, 64, 0, 2, &c, 1000, NULL, &d);
        okrc(br_cam_lookup(&c, M3, NULL), -1,
             "a source seen only in reserved frames is not learnt");
    }

    /* a tagged frame is refused before its source reaches the table */
    {
        int cnt = br_cam_count(&c);
        mkframe(f, M2, M3, 0x8100);
        br_fwd_decide(f, 64, 0, 2, &c, 1000, NULL, &d);
        okrc(d.action, BR_DROP, "a tagged frame is dropped");
        okrc(d.reason, BR_R_VLAN_TAGGED, "with the tagged reason");
        okrc(br_cam_count(&c), cnt, "and it teaches the table nothing");
    }

    /* a destination learned on the ingress port must not be reflected */
    mkframe(f, M2, M1, 0x0800);
    br_cam_learn(&c, M2, 1, 2000, &moved, &evicted);
    br_fwd_decide(f, 64, 1, 2, &c, 2000, NULL, &d);
    okrc(d.action, BR_DROP, "a frame for this port's own host is dropped");
    okrc(d.reason, BR_R_NO_EGRESS, "with no-egress");

    /* the caller must never be handed an out-of-range port */
    mkframe(f, M2, M1, 0x0800);
    br_cam_learn(&c, M2, 1, 3000, &moved, &evicted);
    okrc(br_fwd_decide(f, 64, 9, 2, &c, 3000, NULL, &d), -1, "a bad ingress port is rejected");
    okrc(br_fwd_decide(f, 64, 0, 0, &c, 3000, NULL, &d), -1, "a service with no ports is rejected");

    group = "vlan metadata";
    {
        /* The bytes can arrive untagged while the kernel still reports the tag
         * in the auxdata. Reading only the delivered bytes would forward this
         * frame as ordinary untagged traffic. */
        struct br_meta m;
        /* A destination the table has never seen, so the untagged case really
         * is a flood and the comparison is like for like. */
        static const uint8_t UNSEEN[6] = {0x02, 0, 0, 0, 0, 0x55};
        mkframe(f, UNSEEN, M1, 0x0800);
        memset(&m, 0, sizeof(m));
        br_fwd_decide(f, 64, 0, 2, &c, 9000, NULL, &d);
        okrc(d.action, BR_FLOOD, "an untagged frame with no metadata is flooded");
        m.vlan_valid = 1;
        m.vlan_tci = 0x0064;
        m.vlan_tpid = 0x8100;
        br_fwd_decide(f, 64, 0, 2, &c, 9001, &m, &d);
        okrc(d.action, BR_DROP, "a tag reported only in the auxdata is still refused");
        okrc(d.reason, BR_R_VLAN_TAGGED, "with the tagged reason");
        m.vlan_tpid_valid = 1;
        m.vlan_valid = 0;
        br_fwd_decide(f, 64, 0, 2, &c, 9002, &m, &d);
        okrc(d.action, BR_DROP, "a valid tpid alone is enough to refuse");
    }

    group = "names";
    ok(strcmp(br_action_name(BR_FLOOD), "flood") == 0, "actions name themselves");
    ok(strcmp(br_reason_name(BR_R_VLAN_TAGGED), "vlan-tagged") == 0,
       "reasons name themselves");
    br_cam_free(&c);
}

int main(void) {
    printf("saphira-bridge unit tests\n");
    t_mac();
    t_classify();
    t_eth();
    t_cam();
    t_fwd();
    printf("\n%d checks, %d failure(s)\n", tests, failures);
    return failures ? 1 : 0;
}

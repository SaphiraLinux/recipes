/*
 * saphira-bridge - CAM table: bounded, hashed, ageing.
 * BUSL-1.1, see LICENSE.
 *
 * The bound is the whole point. A MAC table fed from arbitrary source
 * addresses in incoming frames is a memory exhaustion target and, in a lab
 * where interfaces are recreated constantly, it also fills with dead entries
 * within a few runs. So entries expire, and the table has a ceiling. Neither
 * is optional decoration; both are why this can be trusted unattended.
 */
#include <stdlib.h>
#include <string.h>

#include "bridge.h"

#define BR_CAM_END 0xffffffffu

uint32_t br_mac_hash(const uint8_t mac[BR_MACLEN]) {
    /* FNV-1a over the six address bytes. Ethernet addresses are not random -
     * the OUI in the first three bytes is constant across a vendor - so a
     * naive mask spreads badly and leaves long chains. */
    uint32_t h = 2166136261u;
    for (int i = 0; i < BR_MACLEN; i++) {
        h ^= mac[i];
        h *= 16777619u;
    }
    h ^= h >> 16;
    h *= 0x85ebca6bu;
    h ^= h >> 13;
    return h;
}

int br_cam_init(struct br_cam *c, int max_entries, int age_secs) {
    memset(c, 0, sizeof(*c));
    if (max_entries < BR_CAM_MIN || max_entries > BR_CAM_MAX) return -1;
    if (age_secs < 1 || age_secs > 86400) return -1;

    uint32_t n = (uint32_t)max_entries * 2;
    /* round up to a power of two so the bucket index is a mask, not a modulo */
    uint32_t p = 1;
    while (p < n) p <<= 1;
    if (p > (1u << 21)) p = 1u << 21;

    c->ents = calloc((size_t)max_entries, sizeof(*c->ents));
    c->buckets = calloc(p, sizeof(*c->buckets));
    if (!c->ents || !c->buckets) { free(c->ents); free(c->buckets); return -1; }
    for (uint32_t i = 0; i < p; i++) c->buckets[i] = BR_CAM_END;

    c->nbuckets = p;
    c->max_entries = max_entries;
    c->age_secs = age_secs;
    return 0;
}

void br_cam_free(struct br_cam *c) {
    free(c->ents);
    free(c->buckets);
    c->ents = NULL;
    c->buckets = NULL;
    c->nbuckets = 0;
}

static uint32_t *br_chain_head(const struct br_cam *c, const uint8_t mac[BR_MACLEN]) {
    if (!c->buckets) return NULL;
    return &c->buckets[br_mac_hash(mac) & (c->nbuckets - 1)];
}

int br_cam_count(const struct br_cam *c) {
    int n = 0;
    for (int i = 0; i < c->max_entries; i++)
        if (c->ents[i].used) n++;
    return n;
}

int br_cam_count_evictable(const struct br_cam *c) {
    int n = 0;
    for (int i = 0; i < c->max_entries; i++)
        if (c->ents[i].used && c->ents[i].last_seen == 0) n++;
    return n;
}

int br_cam_lookup(const struct br_cam *c, const uint8_t mac[BR_MACLEN], int *port) {
    uint32_t *head = br_chain_head(c, mac);
    if (!head) return -1;
    for (uint32_t i = *head; i != BR_CAM_END; i = c->ents[i].next) {
        if (memcmp(c->ents[i].mac, mac, BR_MACLEN) == 0) {
            if (port) *port = c->ents[i].port;
            return 0;
        }
    }
    return -1;
}

static int br_cam_remove(struct br_cam *c, uint32_t idx) {
    uint32_t *head = br_chain_head(c, c->ents[idx].mac);
    if (!head) return -1;
    uint32_t prev = BR_CAM_END, cur = *head;
    while (cur != BR_CAM_END) {
        if (cur == idx) {
            if (prev == BR_CAM_END) *head = c->ents[cur].next;
            else c->ents[prev].next = c->ents[cur].next;
            c->ents[cur].used = 0;
            c->ents[cur].port = -1;
            c->ents[cur].next = BR_CAM_END;
            return 0;
        }
        prev = cur;
        cur = c->ents[cur].next;
    }
    return -1;
}

/* Expire first, then evict. A table that is full of entries past their idle
 * age should give up a dead entry before a live one, and the sweep is the
 * only place that knowledge exists. */
int br_cam_age(struct br_cam *c, time_t now) {
    if (!c->ents) return 0;
    int removed = 0;
    for (int i = 0; i < c->max_entries; i++) {
        if (!c->ents[i].used) continue;
        if (now - c->ents[i].last_seen >= c->age_secs) {
            if (br_cam_remove(c, (uint32_t)i) == 0) {
                c->expired++;
                removed++;
            }
        }
    }
    return removed;
}

static int br_cam_find_free(const struct br_cam *c) {
    for (int i = 0; i < c->max_entries; i++)
        if (!c->ents[i].used) return i;
    return -1;
}

static int br_cam_find_oldest(const struct br_cam *c) {
    int best = -1;
    for (int i = 0; i < c->max_entries; i++) {
        if (!c->ents[i].used) continue;
        if (best < 0 || c->ents[i].last_seen < c->ents[best].last_seen) best = i;
    }
    return best;
}

int br_cam_learn(struct br_cam *c, const uint8_t mac[BR_MACLEN], int port,
                 time_t now, int *moved, int *evicted) {
    if (moved) *moved = 0;
    if (evicted) *evicted = 0;
    if (!c->ents || !c->buckets) return -1;

    /* A source address that moved between ports is the cheap, honest signal
     * that the segment has a loop in it. With no spanning tree, this is how
     * the operator finds out; it is counted and logged, never auto-repaired,
     * because silently healing a lab's miswiring hides the mistake that caused
     * it. */
    uint32_t *head = br_chain_head(c, mac);
    for (uint32_t i = *head; i != BR_CAM_END; i = c->ents[i].next) {
        if (memcmp(c->ents[i].mac, mac, BR_MACLEN) != 0) continue;
        if (c->ents[i].port != port) {
            c->ents[i].port = port;
            c->moved++;
            if (moved) *moved = 1;
        }
        c->ents[i].last_seen = now;
        return 0;
    }

    int slot = br_cam_find_free(c);
    if (slot < 0) {
        br_cam_age(c, now);
        slot = br_cam_find_free(c);
    }
    if (slot < 0) {
        slot = br_cam_find_oldest(c);
        if (slot < 0) return -1;
        br_cam_remove(c, (uint32_t)slot);
        c->evicted++;
        if (evicted) *evicted = 1;
    }

    memcpy(c->ents[slot].mac, mac, BR_MACLEN);
    c->ents[slot].port = port;
    c->ents[slot].last_seen = now;
    c->ents[slot].used = 1;
    c->ents[slot].next = *head;
    *head = (uint32_t)slot;
    c->learnt++;
    return 0;
}

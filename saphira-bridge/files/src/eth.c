/*
 * saphira-bridge - minimal Ethernet header inspection.
 * BUSL-1.1, see LICENSE.
 *
 * Only what forwarding needs: the two addresses and the ethertype. No IP, no
 * ARP, no NDP. If a field is not needed to decide where a frame goes, it is
 * not read.
 */
#include <stdio.h>
#include <string.h>
#include <arpa/inet.h>

#include "bridge.h"

int br_mac_parse(const char *s, uint8_t out[BR_MACLEN]) {
    unsigned v[BR_MACLEN];
    char tail;
    if (sscanf(s, "%x:%x:%x:%x:%x:%x%c", &v[0], &v[1], &v[2], &v[3], &v[4],
               &v[5], &tail) != BR_MACLEN)
        return -1;
    for (int i = 0; i < BR_MACLEN; i++) {
        if (v[i] > 0xff) return -1;
        out[i] = (uint8_t)v[i];
    }
    return 0;
}

void br_mac_format(const uint8_t mac[BR_MACLEN], char *buf, size_t len) {
    snprintf(buf, len, "%02x:%02x:%02x:%02x:%02x:%02x", mac[0], mac[1], mac[2],
             mac[3], mac[4], mac[5]);
}

int br_is_broadcast(const uint8_t mac[BR_MACLEN]) {
    static const uint8_t bcast[BR_MACLEN] = {0xff, 0xff, 0xff, 0xff, 0xff, 0xff};
    return memcmp(mac, bcast, BR_MACLEN) == 0;
}

int br_is_multicast(const uint8_t mac[BR_MACLEN]) {
    /* The I/G bit is the low bit of the first octet. Broadcast is technically
     * a multicast address, so callers that need to tell them apart test
     * broadcast first. */
    return (mac[0] & 0x01) != 0;
}

/* 01:80:C2:00:00:00 through 01:80:C2:00:00:0f are reserved by IEEE 802.1D and
 * carry protocol payloads - spanning tree, provider bridging, LLDP and the
 * rest. They are not ordinary traffic: they must be neither learnt from nor
 * flooded as if they were, and a bridge that forwards them as data is a
 * bridge that can be driven by another bridge's control traffic. */
int br_is_reserved(const uint8_t mac[BR_MACLEN]) {
    if (mac[0] != 0x01 || mac[1] != 0x80 || mac[2] != 0xc2) return 0;
    if (mac[3] != 0x00 || mac[4] != 0x00) return 0;
    return mac[5] <= 0x0f;
}

unsigned br_ethertype(const uint8_t *frame, size_t len) {
    if (len < BR_ETH_HDR_LEN) return 0;
    return (unsigned)((frame[12] << 8) | frame[13]);
}

/* Tagging is refused rather than handled. A tagged frame's real destination is
 * not at offset 0 and its real ethertype is not at offset 12, so forwarding it
 * untagged would hand the next port a frame whose headers mean something else
 * entirely. Dropping and counting is the only honest response for a tool that
 * does not implement VLANs. */
int br_is_vlan_tagged(const uint8_t *frame, size_t len) {
    unsigned t = br_ethertype(frame, len);
    return t == 0x8100u || t == 0x88a8u || t == 0x9100u;
}

void br_ethertype_format(unsigned type, char *buf, size_t len) {
    snprintf(buf, len, "0x%04x", type);
}

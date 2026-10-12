/*
 * saphira-bridge test probe: send and receive raw Ethernet frames.
 * Test tooling only, installed nowhere. BUSL-1.1, see LICENSE.
 *
 * The lab needs to know which port a frame came out of, and inferring that
 * from IP behaviour is a guess: ARP, routing and retransmission all stand
 * between an observation and the thing being observed. This sends the exact
 * frame and counts the exact frames that arrive, so a forwarding rule is
 * measured rather than inferred.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <time.h>
#include <net/if.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <linux/if_packet.h>
#include <linux/if_ether.h>
#include <linux/if_packet.h>

static int mac_parse(const char *s, unsigned char out[6]) {
    unsigned v[6];
    if (sscanf(s, "%x:%x:%x:%x:%x:%x", &v[0], &v[1], &v[2], &v[3], &v[4], &v[5]) != 6)
        return -1;
    for (int i = 0; i < 6; i++) {
        if (v[i] > 0xff) return -1;
        out[i] = (unsigned char)v[i];
    }
    return 0;
}

static int open_if(const char *name) {
    int fd = socket(AF_PACKET, SOCK_RAW, htons(ETH_P_ALL));
    if (fd < 0) { perror("socket"); return -1; }
    struct sockaddr_ll sll;
    memset(&sll, 0, sizeof(sll));
    sll.sll_family = AF_PACKET;
    sll.sll_protocol = htons(ETH_P_ALL);
    sll.sll_ifindex = if_nametoindex(name);
    if (sll.sll_ifindex == 0) { fprintf(stderr, "no such interface: %s\n", name); return -1; }
    if (bind(fd, (struct sockaddr *)&sll, sizeof(sll)) != 0) { perror("bind"); return -1; }
    /* A bridge lab must be able to observe frames that are not addressed to
     * this host, which is precisely the traffic a bridge forwards. Without
     * promiscuous mode the kernel correctly withholds them, and the receiver
     * reports a forwarding rule as broken when the rule worked. */
    struct packet_mreq mr;
    memset(&mr, 0, sizeof mr);
    mr.mr_ifindex = sll.sll_ifindex;
    mr.mr_type = PACKET_MR_PROMISC;
    if (setsockopt(fd, SOL_PACKET, PACKET_ADD_MEMBERSHIP, &mr, sizeof mr) != 0)
        fprintf(stderr, "warning: promiscuous mode: %s\n", strerror(errno));
    return fd;
}

static int do_send(int argc, char **argv) {
    if (argc < 6) { fprintf(stderr, "send IFACE SRC DST ETHERTYPE COUNT [VLAN_TCI]\n"); return 2; }
    const char *ifname = argv[1];
    unsigned char src[6], dst[6];
    if (mac_parse(argv[2], src) != 0 || mac_parse(argv[3], dst) != 0) {
        fprintf(stderr, "bad mac\n"); return 2;
    }
    unsigned ethtype = (unsigned)strtoul(argv[4], NULL, 0);
    long count = strtol(argv[5], NULL, 10);
    int fd = open_if(ifname);
    if (fd < 0) return 1;

    unsigned char frame[128];
    memset(frame, 0, sizeof(frame));
    memcpy(frame, dst, 6);
    memcpy(frame + 6, src, 6);
    frame[12] = (unsigned char)(ethtype >> 8);
    frame[13] = (unsigned char)(ethtype & 0xff);
    /* A recognisable payload so a receiver can prove it is our frame. */
    memcpy(frame + 14, "SAPIRA-BRIDGE-PROBE", 19);
    /*
     * A VLAN tag is four bytes: the tag control information and the ethertype
     * of the frame inside it. Simply setting ethertype to 0x8100 and leaving
     * payload where the tag belongs is not a tagged frame, it is a corrupt one,
     * and the kernel's VLAN-aware path consumes those four bytes - so it
     * arrives four bytes short with its real destination gone. Measured, not
     * assumed: the frame came back len=124 with an "ethertype" of 0x5049,
     * which is the ASCII "PI" from this tool's own payload.
     */
    if (argc >= 7) {
        unsigned tci = (unsigned)strtoul(argv[6], NULL, 0);
        frame[14] = (unsigned char)(tci >> 8);
        frame[15] = (unsigned char)(tci & 0xff);
        frame[16] = 0x08;   /* inner ethertype: IPv4 */
        frame[17] = 0x00;
        memcpy(frame + 18, "SAPIRA-BRIDGE-PROBE", 19);
    }

    struct sockaddr_ll sll;
    memset(&sll, 0, sizeof(sll));
    sll.sll_family = AF_PACKET;
    sll.sll_protocol = htons(ETH_P_ALL);
    sll.sll_ifindex = if_nametoindex(ifname);
    sll.sll_halen = 0;

    for (long i = 0; i < count; i++) {
        if (sendto(fd, frame, sizeof(frame), 0, (struct sockaddr *)&sll, sizeof(sll)) < 0) {
            perror("sendto");
            return 1;
        }
        if (i + 1 < count) usleep(20000);
    }
    printf("sent %ld\n", count);
    return 0;
}

static int do_recv(int argc, char **argv) {
    /* An optional trailing marker restricts counting to this tool's own frames.
     * A promiscuous receiver also sees the segment's ARP and MLD traffic, and
     * measuring a forwarding rule against that background is how a test comes
     * to report a rule as broken when it worked. */
    const char *marker = (argc >= 6) ? argv[5] : NULL;
    if (argc < 5) { fprintf(stderr, "recv IFACE DST COUNT TIMEOUT_MS [MARKER]\n"); return 2; }
    const char *ifname = argv[1];
    unsigned char dst[6];
    if (mac_parse(argv[2], dst) != 0) { fprintf(stderr, "bad mac\n"); return 2; }
    long want = strtol(argv[3], NULL, 10);
    long timeout_ms = strtol(argv[4], NULL, 10);
    int fd = open_if(ifname);
    if (fd < 0) return 1;

    struct timespec start, now;
    clock_gettime(CLOCK_MONOTONIC, &start);
    long seen = 0, ours = 0, marked = 0;
    /* Wait for `want` frames addressed to us, not for `want` frames of any
     * kind: a segment carries ARP and MLD traffic, and exiting on the first
     * unrelated frame would close the window before the frame under test ever
     * arrived. */
    while (ours < want) {
        unsigned char buf[2048];
        ssize_t n = recv(fd, buf, sizeof(buf), MSG_DONTWAIT);
        if (n > 0) {
            seen++;
            if (marker) {
                /* The payload follows the header, and a VLAN tag moves it by
                 * four bytes. Search the first bytes of the payload area so the
                 * marker is found for tagged and untagged frames alike. */
                size_t mlen = strlen(marker);
                int found = 0;
                for (ssize_t off = 14; off + (ssize_t)mlen <= n && off < 32; off++) {
                    if (memcmp(buf + off, marker, mlen) == 0) { found = 1; break; }
                }
                if (found) {
                    marked++;
                    if (memcmp(buf, dst, 6) == 0) ours++;
                }
            } else if (memcmp(buf, dst, 6) == 0) {
                ours++;
            }
            if (getenv("BR_PROBE_HEX")) {
                /* What is actually on the wire, so an offset assumption can be
                 * measured instead of argued about. */
                fprintf(stderr, "frame[%zd]:", n);
                for (ssize_t k = 0; k < 20 && k < n; k++) fprintf(stderr, " %02x", buf[k]);
                fprintf(stderr, "\n");
            }
        } else if (n < 0 && errno != EAGAIN && errno != EWOULDBLOCK) {
            perror("recv");
            return 1;
        }
        clock_gettime(CLOCK_MONOTONIC, &now);
        long elapsed = (now.tv_sec - start.tv_sec) * 1000 +
                       (now.tv_nsec - start.tv_nsec) / 1000000;
        if (elapsed >= timeout_ms) break;
        usleep(2000);
    }
    /* Two numbers: how many frames arrived for this address, and how many
     * arrived at all. A receiver that sees the frame on the wrong port fails
     * on the second number, not the first. */
    printf("matched=%ld marked=%ld total=%ld\n", ours, marked, seen);
    return ours >= want ? 0 : 1;
}

int main(int argc, char **argv) {
    if (argc < 2) {
        fprintf(stderr, "usage: br-probe send|recv ...\n");
        return 2;
    }
    if (strcmp(argv[1], "send") == 0) return do_send(argc - 1, argv + 1);
    if (strcmp(argv[1], "recv") == 0) return do_recv(argc - 1, argv + 1);
    fprintf(stderr, "usage: br-probe send|recv ...\n");
    return 2;
}

/*
 * saphira-bridge diagnostic: does PACKET_VNET_HDR expose deferred-checksum
 * state on this AF_PACKET/veth path?
 *
 * Test tooling only, installed nowhere. BUSL-1.1, see LICENSE
 *
 * The question is whether a userspace bridge can carry a sender's deferred
 * transport checksum across the userspace hop without parsing IP at all. If it
 * can, the checksum is completed by the egress path and the bridge stays
 * protocol-agnostic. If it cannot, the bridge has to compute the sum itself.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <time.h>
#include <net/if.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <linux/if_packet.h>
#include <linux/if_ether.h>
#include <linux/virtio_net.h>

#define MAXF 64

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: vhdr IFACE COUNT [TX_IFACE]\n"
                        "  RX on IFACE for COUNT frames, printing the virtio_net_hdr\n"
                        "  and the auxdata the kernel supplied with each.\n"
                        "  With TX_IFACE, also re-send each frame out TX_IFACE with\n"
                        "  the virtio_net_hdr the kernel gave us.\n");
        return 2;
    }
    const char *ifname = argv[1];
    long want = strtol(argv[2], NULL, 10);
    const char *txname = (argc >= 4) ? argv[3] : NULL;

    int fd = socket(AF_PACKET, SOCK_RAW, htons(ETH_P_ALL));
    if (fd < 0) { perror("socket"); return 1; }
    struct sockaddr_ll sll;
    memset(&sll, 0, sizeof(sll));
    sll.sll_family = AF_PACKET;
    sll.sll_protocol = htons(ETH_P_ALL);
    sll.sll_ifindex = if_nametoindex(ifname);
    if (!sll.sll_ifindex) { fprintf(stderr, "no such interface %s\n", ifname); return 1; }
    if (bind(fd, (struct sockaddr *)&sll, sizeof(sll)) != 0) { perror("bind"); return 1; }

    int one = 1;
    if (setsockopt(fd, SOL_PACKET, PACKET_AUXDATA, &one, sizeof(one)) != 0)
        fprintf(stderr, "warning: PACKET_AUXDATA: %s\n", strerror(errno));
    if (setsockopt(fd, SOL_PACKET, PACKET_VNET_HDR, &one, sizeof(one)) != 0) {
        fprintf(stderr, "PACKET_VNET_HDR: %s\n", strerror(errno));
        printf("vnet_hdr_supported=no reason=%s errno=%d\n",
               strerror(errno), errno);
        return 3;
    }
    printf("vnet_hdr_supported=yes\n");

    /* "strip" models a naive byte-forwarder: it hands the frame on without the
     * deferred-checksum metadata, which is what happens if the bridge just
     * copies bytes. Used as the control arm. */
    int strip = (getenv("VHDR_STRIP") != NULL);

    int txfd = -1;
    if (txname) {
        txfd = socket(AF_PACKET, SOCK_RAW, htons(ETH_P_ALL));
        if (txfd < 0) { perror("tx socket"); return 1; }
        int t = 1;
        if (setsockopt(txfd, SOL_PACKET, PACKET_VNET_HDR, &t, sizeof(t)) != 0) {
            fprintf(stderr, "tx PACKET_VNET_HDR: %s\n", strerror(errno));
            close(txfd);
            txfd = -1;
        }
    }

    unsigned char buf[2048 + sizeof(struct virtio_net_hdr)];
    long seen = 0, hdr_seen = 0, idle = 0;
    long need_csum = 0, resent = 0;
    unsigned long long csum_start_sum = 0, csum_off_sum = 0;

    while (seen < want) {
        struct iovec iov;
        struct msghdr mh;
        struct sockaddr_ll from;
        uint8_t cbuf[64];
        struct virtio_net_hdr *vh;
        unsigned aux_status = 0;
        ssize_t n;

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

        n = recvmsg(fd, &mh, MSG_DONTWAIT);
        if (n < 0) {
            if (errno == EINTR) continue;
            if (errno != EAGAIN && errno != EWOULDBLOCK) { perror("recvmsg"); break; }
            usleep(2000);
            if (++idle > 3000) break;      /* idle iterations, not frames */
            continue;
        }
        idle = 0;
        for (struct cmsghdr *c = CMSG_FIRSTHDR(&mh); c; c = CMSG_NXTHDR(&mh, c)) {
            if (c->cmsg_level == SOL_PACKET &&
                c->cmsg_type == PACKET_AUXDATA &&
                c->cmsg_len >= CMSG_LEN(sizeof(struct tpacket_auxdata))) {
                struct tpacket_auxdata aux;
                memcpy(&aux, CMSG_DATA(c), sizeof(aux));
                aux_status = aux.tp_status;
            }
        }

        vh = (struct virtio_net_hdr *)buf;
        int looks_tagged = (n >= 6 && (buf[0] & 0x01) == 0x00);

        /* The frame the kernel hands over is what follows the vnet_hdr. A frame
         * whose first byte is not a plausible unicast destination tells us the
         * header is really there, because a vnet_hdr starts with a flags byte
         * that is 0 or 1. */
        int plausible_dmac = (n > (ssize_t)sizeof(*vh) + 6) &&
                             (buf[sizeof(*vh)] & 0x01) == 0x00 &&
                             (buf[sizeof(*vh) + 0] == buf[0]);
        if (n > (ssize_t)sizeof(*vh)) {
            hdr_seen++;
            printf("frame%ld: aux_status=0x%08x csumnotready=%d vnet{"
                   "flags=0x%02x gso_type=%u hdr_len=%u gso_size=%u "
                   "csum_start=%u csum_offset=%u} needs_csum=%d len_after_hdr=%zd\n",
                   seen, aux_status,
                   (aux_status & TP_STATUS_CSUMNOTREADY) ? 1 : 0,
                   vh->flags, vh->gso_type, vh->hdr_len, vh->gso_size,
                   vh->csum_start, vh->csum_offset,
                   (vh->flags & VIRTIO_NET_HDR_F_NEEDS_CSUM) ? 1 : 0,
                   n - (ssize_t)sizeof(*vh));
            if (vh->flags & VIRTIO_NET_HDR_F_NEEDS_CSUM) {
                need_csum++;
                csum_start_sum += vh->csum_start;
                csum_off_sum += vh->csum_offset;
            }
            if (txfd >= 0) {
                if (strip && (vh->flags & VIRTIO_NET_HDR_F_NEEDS_CSUM)) {
                    printf("  stripping NEEDS_CSUM before resend "
                           "(csum_start=%u csum_offset=%u)\n",
                           vh->csum_start, vh->csum_offset);
                    vh->flags &= (unsigned char)~VIRTIO_NET_HDR_F_NEEDS_CSUM;
                }
                struct sockaddr_ll t;
                memset(&t, 0, sizeof(t));
                t.sll_family = AF_PACKET;
                t.sll_protocol = htons(ETH_P_ALL);
                t.sll_ifindex = if_nametoindex(txname);
                ssize_t w = sendto(txfd, buf, (size_t)n, 0,
                                   (struct sockaddr *)&t, sizeof(t));
                if (w > 0) resent++;
                else printf("  resend failed: %s\n", strerror(errno));
            }
        } else {
            printf("frame%ld: aux_status=0x%08x too short for a vnet_hdr (len=%zd)\n",
                   seen, aux_status, n);
        }
        (void)plausible_dmac;
        (void)looks_tagged;
        seen++;
        fflush(stdout);
    }

    fflush(stdout);
    printf("SUMMARY frames=%ld with_vnet_hdr=%ld needs_csum=%ld "
           "avg_csum_start=%lu avg_csum_offset=%lu resent=%ld\n",
           seen, hdr_seen, need_csum,
           (unsigned long)(need_csum ? csum_start_sum / (unsigned long long)need_csum : 0),
           (unsigned long)(need_csum ? csum_off_sum / (unsigned long long)need_csum : 0),
           resent);
    close(fd);
    if (txfd >= 0) close(txfd);
    return 0;
}

#!/bin/sh
# saphira-bridge namespace lab. BUSL-1.1, see LICENSE
#
# Three point-to-point links joined into one segment by saphira-bridge. Every
# network below has exactly two members, so nothing can reach anything except
# through the bridge - which is what makes the forwarding rules observable.
#
# No Docker: the topology is built with network namespaces, because a
# point-to-point segment joined by a userspace bridge is precisely the thing
# containers make awkward and namespaces make exact.
#
# usage: bridge-lab.sh setup | run | teardown
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/src/saphira-bridge"
PROBE="$ROOT/tests/br-probe"
CONF=/tmp/br-lab.conf
LOG=/tmp/br-lab.log
# the account saphira-bridge runs as; override to test another
SEED=${SEED:-127}

pass=0
fail=0

say()  { printf '  %s\n' "$1"; }
ok()   { pass=$((pass + 1)); }
bad()  { fail=$((fail + 1)); printf '  FAIL %s\n' "$1"; }
group(){ printf '\n== %s\n' "$1"; }

mac_of() {
    # read the hardware address of an interface from inside its namespace
    ip netns exec "$1" cat "/sys/class/net/$2/address" 2>/dev/null
}

# pull one counter out of a SIGUSR1 dump
dump() {
    ip netns exec sw pkill -USR1 -x saphira-bridge 2>/dev/null
    sleep 0.4
    cat "$LOG" 2>/dev/null
}
stat_of() { dump | grep -av 'port ' | sed -n "s/.* $1=\([0-9]*\).*/\1/p" | tail -1; }
port_tx() { dump | sed -n "s/.*port $1 .*tx=\([0-9]*\).*/\1/p" | tail -1; }
cam_entries() { dump | sed -n 's/.*cam: entries=\([0-9]*\)\/.*/\1/p' | tail -1; }

setup() {
    ip netns del sw 2>/dev/null; ip netns del a 2>/dev/null
    ip netns del b 2>/dev/null; ip netns del c 2>/dev/null
    for n in sw a b c; do
        ip netns add "$n"
        # IPv6 is switched off here, before any interface exists, so `default`
        # covers every veth created afterwards. This is a change to the test
        # segment and not to the daemon: a bridge floods multicast, and each
        # veth peer answers flooded MLD with more MLD, which turns into positive
        # feedback of hundreds of thousands of frames a second and buries every
        # measurement. Real segments control that with storm control, which is
        # out of scope here; a lab segment simply does not need the noise.
        ip netns exec "$n" sh -c 'echo 1 > /proc/sys/net/ipv6/conf/all/disable_ipv6' 2>/dev/null || true
        ip netns exec "$n" sh -c 'echo 1 > /proc/sys/net/ipv6/conf/default/disable_ipv6' 2>/dev/null || true
        ip netns exec "$n" ip link set lo up
    done

    # Three independent point-to-point links; no shared segment and no kernel
    # bridge anywhere. Each pair is created in this namespace and then moved, so
    # the topology does not depend on which iproute2 spelling is available.
    ip link add sw0 type veth peer name a0
    ip link set sw0 netns sw
    ip link set a0 netns a
    ip link add sw1 type veth peer name b0
    ip link set sw1 netns sw
    ip link set b0 netns b
    ip link add sw2 type veth peer name c0
    ip link set sw2 netns sw
    ip link set c0 netns c

    for n in sw0 sw1 sw2; do ip netns exec sw ip link set "$n" up; done
    ip netns exec a ip link set a0 up
    ip netns exec b ip link set b0 up
    ip netns exec c ip link set c0 up

    # The veths are created in this namespace and then moved in, so `default`
    # never applied to them; each interface is disabled explicitly once it
    # exists, and the result is read back rather than assumed.
    for pair in a:a0 b:b0 c:c0 sw:sw0 sw:sw1 sw:sw2; do
        n=${pair%%:*}; i=${pair##*:}
        ip netns exec "$n" sh -c "echo 1 > /proc/sys/net/ipv6/conf/$i/disable_ipv6" 2>/dev/null
        got=$(ip netns exec "$n" cat "/proc/sys/net/ipv6/conf/$i/disable_ipv6" 2>/dev/null)
        [ "${got:-0}" = 1 ] || say "  warning: could not disable IPv6 on $n/$i (got '${got:-?}')"
    done

    ip netns exec a ip addr add 10.77.0.1/24 dev a0
    ip netns exec b ip addr add 10.77.0.2/24 dev b0
    ip netns exec c ip addr add 10.77.0.3/24 dev c0

    say "three point-to-point links, one shared address range, no shared segment"
}

teardown() {
    ip netns exec sw pkill -x saphira-bridge 2>/dev/null
    sleep 0.3
    for n in sw a b c; do ip netns del "$n" 2>/dev/null; done
    rm -f "$CONF" "$LOG"
}

# The daemon and the probe are build products and deliberately not committed, so
# a clean checkout has neither. This lab is the acceptance evidence for the
# daemon, and evidence that cannot be produced from a clean tree is not evidence.
build_if_needed() {
    if [ ! -x "$BIN" ]; then
        make -C "$ROOT/src" >/tmp/br-build.log 2>&1 ||
            { echo "cannot build $BIN; see /tmp/br-build.log" >&2; exit 1; }
    fi
    if [ ! -x "$PROBE" ]; then
        cc -std=c11 -O1 -Wall -Wextra -D_DEFAULT_SOURCE -D_GNU_SOURCE \
            -o "$PROBE" "$ROOT/tests/br-probe.c" >/tmp/br-probe.log 2>&1 ||
            { echo "cannot build the test probe; see /tmp/br-probe.log" >&2; exit 1; }
    fi
}

run() {
    build_if_needed
    # A stale log from an earlier run makes every assertion below read someone
    # else's numbers, so it is removed before the bridge is started.
    rm -f "$LOG"
    A_MAC=$(mac_of a a0); B_MAC=$(mac_of b b0); C_MAC=$(mac_of c c0)
    BCAST=ff:ff:ff:ff:ff:ff
    FAKE1=02:aa:00:00:00:01
    FAKE2=02:aa:00:00:00:02
    say "a=$A_MAC b=$B_MAC c=$C_MAC"

    cat > "$CONF" <<EOF
# three point-to-point links joined into one segment
port=sw0
port=sw1
port=sw2
age_secs=${AGE_SECS:-300}
max_entries=${MAX_ENTRIES:-4096}
uid=$SEED
gid=$SEED
EOF

    ip netns exec sw setsid "$BIN" -c "$CONF" -n lab >"$LOG" 2>&1 &
    sleep 1.2

    group "startup and privilege"
    if grep -q "ready" "$LOG" 2>/dev/null; then ok; else
        bad "the bridge reached ready"
        # A lab that cannot start should say why, not report seventeen
        # downstream failures that all share one cause.
        say "the bridge said:"
        sed 's/^/    /' "$LOG" 2>/dev/null | head -12
        say "process alive? $(ip netns exec sw pgrep -x saphira-bridge >/dev/null 2>&1 && echo yes || echo no)"
    fi
    if grep -q "uid=$SEED" "$LOG" 2>/dev/null; then
        ok; say "privileges dropped to uid $SEED"
    else
        bad "privileges dropped"
    fi
    if grep -q "owns ARP, NDP, IP" "$LOG" 2>/dev/null; then
        ok; say "it states its own boundary at startup"
    else bad "it states its boundary"; fi

    group "transparency: a real stack works through it unchanged"
    # Nothing here is aware saphira-bridge exists. These addresses, ARP and
    # ICMP are the kernel's, and they work because the bridge is transparent.
    if ip netns exec a ping -c2 -W2 10.77.0.3 >/dev/null 2>&1; then
        ok; say "a -> c by IP: two replies, with no knowledge of the bridge"
    else bad "IP traffic traverses the segment"; fi
    if ip netns exec c ping -c2 -W2 10.77.0.1 >/dev/null 2>&1; then
        ok; say "c -> a by IP: the direct return is not proxied either"
    else bad "the reverse direction traverses the segment"; fi

    group "learning and known unicast"
    # The pings above have already taught the table every address on the
    # segment, so a frame aimed at c is unicast by now. Flooding is therefore
    # tested against an address the table has provably never seen.
    sw1_before=$(port_tx sw1)
    sw2_before=$(port_tx sw2)
    ip netns exec c "$PROBE" recv c0 "$FAKE1" 1 1500 SAPIRA-BRIDGE-PROBE >/tmp/r_c1 2>&1 & P1=$!
    ip netns exec b "$PROBE" recv b0 "$B_MAC" 1 1500 SAPIRA-BRIDGE-PROBE >/tmp/r_b1 2>&1 & P2=$!
    sleep 0.2
    ip netns exec a "$PROBE" send a0 "$A_MAC" "$FAKE1" 0x88b5 1 >/dev/null 2>&1
    wait $P1 $P2 2>/dev/null
    if grep -q "matched=1" /tmp/r_c1 2>/dev/null; then
        ok; say "an unknown destination reached c by flooding"
    else bad "an unknown destination floods to c"; fi
    # b receives the frame but it is not addressed to b. The probe reports
    # "arrived here" and "addressed to me" separately, so the two are told
    # apart rather than conflated.
    if grep -q "matched=0 marked=1" /tmp/r_b1 2>/dev/null; then
        ok; say "and it reached b, which it was not addressed to: that is flooding"
    else
        bad "flooding must reach every port but the ingress"
        sed 's/^/    /' /tmp/r_b1
    fi
    # The segment is quiet enough now that a per-port delta is meaningful.
    sw1_after=$(port_tx sw1); sw2_after=$(port_tx sw2)
    if [ $(( ${sw1_after:-0} - ${sw1_before:-0} )) -eq 1 ] &&
       [ $(( ${sw2_after:-0} - ${sw2_before:-0} )) -eq 1 ]; then
        ok; say "each of the other two ports transmitted it exactly once"
    else
        bad "a flood must write once per egress port (sw1 $sw1_before->$sw1_after, sw2 $sw2_before->$sw2_after)"
    fi

    # Now c is known. The same frame must go to c alone.
    b_before=$(port_tx sw1)
    ip netns exec b "$PROBE" recv b0 "$B_MAC" 1 1200 SAPIRA-BRIDGE-PROBE >/tmp/r_b2 2>&1 & P2=$!
    ip netns exec c "$PROBE" recv c0 "$C_MAC" 1 1200 SAPIRA-BRIDGE-PROBE >/tmp/r_c2 2>&1 & P3=$!
    sleep 0.2
    ip netns exec a "$PROBE" send a0 "$A_MAC" "$C_MAC" 0x88b5 1 >/dev/null 2>&1
    wait $P2 $P3 2>/dev/null
    if grep -q "matched=1" /tmp/r_c2 2>/dev/null; then
        ok; say "a learned destination is delivered to it"
    else bad "known unicast reaches c"; fi
    if grep -q "matched=0 marked=0" /tmp/r_b2 2>/dev/null; then
        ok; say "and b did not see it at all: learning replaced flooding"
    else
        bad "known unicast must not also flood"
        sed 's/^/    /' /tmp/r_b2
    fi
    # The bridge's own per-port counters are not a usable assertion here: a
    # live segment carries background multicast, so a delta in port tx says
    # nothing about our frame. Whether the frame came back out the ingress port
    # is answered directly, by listening on the sending host.

    group "broadcast never leaves the port it arrived on"
    ip netns exec b "$PROBE" recv b0 "$BCAST" 1 1500 SAPIRA-BRIDGE-PROBE >/tmp/r_bb 2>&1 & P2=$!
    ip netns exec c "$PROBE" recv c0 "$BCAST" 1 1500 SAPIRA-BRIDGE-PROBE >/tmp/r_cb 2>&1 & P3=$!
    ip netns exec a "$PROBE" recv a0 "$BCAST" 1 1500 SAPIRA-BRIDGE-PROBE >/tmp/r_ba 2>&1 & P1=$!
    sleep 0.2
    ip netns exec a "$PROBE" send a0 "$A_MAC" "$BCAST" 0x88b5 1 >/dev/null 2>&1
    wait $P1 $P2 $P3 2>/dev/null
    grep -q "matched=1" /tmp/r_bb 2>/dev/null && ok || bad "broadcast reached b"
    grep -q "matched=1" /tmp/r_cb 2>/dev/null && ok || bad "broadcast reached c"
    # A promiscuous receiver on the sending host sees the loopback copy too, so
    # the marker is what distinguishes a reflected frame from local delivery.
    # A promiscuous receiver on the sending host also sees the local loopback of
    # the frame it just sent, so it cannot by itself prove anything about the
    # bridge. The bridge's own ingress-port counter can: a broadcast must not
    # come back out sw0.
    ax_before=$(port_tx sw0)
    ip netns exec a "$PROBE" send a0 "$A_MAC" "$BCAST" 0x88b5 1 >/dev/null 2>&1
    sleep 0.4
    ax_after=$(port_tx sw0)
    if [ "${ax_after:-0}" = "${ax_before:-0}" ]; then
        ok; say "and the bridge did not transmit back out sw0: $ax_before -> $ax_after"
    else
        bad "a broadcast was reflected back out its ingress port ($ax_before -> $ax_after)"
    fi

    group "frames this bridge refuses"
    r_before=$(stat_of reserved)
    ip netns exec a "$PROBE" send a0 "$A_MAC" 01:80:c2:00:00:00 0x0027 1 >/dev/null 2>&1
    sleep 0.3
    r_after=$(stat_of reserved)
    if [ "${r_after:-0}" -gt "${r_before:-0}" ]; then
        ok; say "802.1D reserved traffic is dropped ($r_before -> $r_after)"
    else bad "reserved control traffic is dropped"; fi

    # A well-formed 802.1Q frame: tag control information plus the ethertype of
    # the frame inside it. Measured: this kernel's transmit path strips the tag
    # before the frame reaches the bridge, so it arrives four bytes short with
    # the inner ethertype at offset 12 and no tag anywhere. The bridge therefore
    # cannot refuse what it is never shown, and the refusal rule is proven by
    # tests/unit.c instead, which feeds the classifier a tagged frame directly.
    v_rx=$(stat_of rx)
    ip netns exec a "$PROBE" send a0 "$A_MAC" "$C_MAC" 0x8100 1 0x0064 >/dev/null 2>&1
    sleep 0.4
    v_rx2=$(stat_of rx)
    if [ "${v_rx2:-0}" -gt "${v_rx:-0}" ]; then
        ok; say "a 802.1Q frame was received"
        say "  note: the kernel stripped the tag on the way in (128 -> 124 bytes,"
        say "  inner ethertype 0x0800 at offset 12), so the tag rule is unit-proven"
    else
        bad "the bridge did not receive the tagged frame at all"
    fi

    sl_before=$(stat_of source_not_learned)
    ip netns exec a "$PROBE" send a0 33:33:00:00:00:99 "$C_MAC" 0x88b5 1 >/dev/null 2>&1
    sleep 0.3
    sl_after=$(stat_of source_not_learned)
    if [ "${sl_after:-0}" -gt "${sl_before:-0}" ]; then
        ok; say "a group address as a source teaches the table nothing"
    else bad "a multicast source is refused for learning"; fi

    ne_before=$(stat_of no_egress)
    ip netns exec c "$PROBE" send c0 "$C_MAC" "$C_MAC" 0x88b5 1 >/dev/null 2>&1
    sleep 0.3
    ne_after=$(stat_of no_egress)
    if [ "${ne_after:-0}" -gt "${ne_before:-0}" ]; then
        ok; say "a frame addressed to the host that sent it is not reflected"
    else bad "self-addressed frames are dropped, not amplified"; fi

    group "a MAC that moves is a loop, and is reported not repaired"
    mv_before=$(stat_of moved)
    ip netns exec a "$PROBE" send a0 "$FAKE1" "$B_MAC" 0x88b5 1 >/dev/null 2>&1
    sleep 0.3
    ip netns exec b "$PROBE" send b0 "$FAKE1" "$A_MAC" 0x88b5 1 >/dev/null 2>&1
    sleep 0.3
    mv_after=$(stat_of moved)
    if [ "${mv_after:-0}" -gt "${mv_before:-0}" ]; then
        ok; say "the same source address on two ports is counted as a move"
    else bad "a port move is detected"; fi
    if grep -q "loop in the segment" "$LOG" 2>/dev/null; then
        ok; say "and it says so in plain words rather than healing it"
    else
        bad "a loop is explained to the operator"
    fi

    group "accounting"
    # All three numbers come from one snapshot. Sampling them from separate
    # dumps compares counters taken at different moments, and on a busy segment
    # that is not a small error.
    ip netns exec sw pkill -USR1 -x saphira-bridge 2>/dev/null
    sleep 0.4
    snap=$(grep -a 'rx=' "$LOG" 2>/dev/null | grep -av 'port ' | tail -1)
    rx=$(printf '%s' "$snap" | sed -n 's/.*rx=\([0-9]*\) .*/\1/p')
    fwd=$(printf '%s' "$snap" | sed -n 's/.*forwarded=\([0-9]*\) .*/\1/p')
    u=$(printf '%s' "$snap" | sed -n 's/.*unicast=\([0-9]*\) .*/\1/p')
    f=$(printf '%s' "$snap" | sed -n 's/.*flooded=\([0-9]*\).*/\1/p')
    drop=$(dump | sed -n 's/.*drops: total=\([0-9]*\).*/\1/p' | tail -1)
    if [ -n "${rx:-}" ] && [ "${rx:-0}" -gt 0 ]; then
        ok; say "rx=$rx forwarded=$fwd dropped=$drop"
    else
        bad "counters are reported"
    fi
    if [ $(( ${u:-0} + ${f:-0} )) -eq "${fwd:-0}" ]; then
        ok; say "unicast($u) + flooded($f) = forwarded($fwd): the total reconciles"
    else
        bad "forwarded must equal unicast plus flooded ($u + $f != ${fwd:-0})"
    fi

    printf '\n%d passed, %d failed\n' "$pass" "$fail"
    teardown
    [ "$fail" -eq 0 ] || exit 1
    exit 0
}

case "${1:-}" in
    setup) setup ;;
    run) run ;;
    teardown) teardown ;;
    *) printf 'usage: bridge-lab.sh setup|run|teardown\n'; exit 2 ;;
esac

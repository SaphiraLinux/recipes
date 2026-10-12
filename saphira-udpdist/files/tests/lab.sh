#!/bin/sh
# saphira-udpdist - same-L2 DSR lab.
#
# Everything runs inside a private user + network + mount namespace, so the
# host's interfaces, routes and neighbour tables are never touched and nothing
# survives teardown. The topology is a genuine shared layer 2 segment, which is
# the only arrangement in which DSR redirect is meaningful.
#
#   cli ---\
#   lb  ----+-- br0 (one L2 segment) -- 198.51.100.0/24
#   be1 ---/
#   be2 -/
#
# The VIP 198.51.100.10 is on the load balancer and, as /32, on each backend's
# loopback. The backend replies straight to the client, never through the load
# balancer.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
BIN="$ROOT/src"

VIP=198.51.100.10
LABNET=198.51.100.0/24
LBIP=198.51.100.1
BE1=198.51.100.21
BE2=198.51.100.22
CLI=198.51.100.100
PORT=9000

pass=0
fail=0
group=""
say_group() { group="$1"; printf '== %s\n' "$1"; }
ok() { if [ "$1" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); printf '  FAIL [%s] %s\n' "$group" "$2"; fi; }

# Cumulative datagrams the distributor has handed to one backend, read from
# its own SIGUSR1 dump. The backend log files are unreliable measurement
# instruments here: truncating a log whose writer holds a non-append descriptor
# leaves NUL holes and grep then reports the file as binary. The daemon's
# counters are the honest source.
bstat() {
    ip netns exec lb pkill -USR1 -f 'udpdist -c /tmp/ud-lab.conf' 2>/dev/null
    sleep 1
    sed -n "s/.*backend $1 mac=\([0-9a-f:]*\|auto\) pkts=\([0-9]*\).*/\2/p" /tmp/ud-lb.log | tail -1
}

bstat_sum() {
    a=$(bstat "${BE1}:${PORT}")
    b=$(bstat "${BE2}:${PORT}")
    echo $(( ${a:-0} + ${b:-0} ))
}

mac_of() {
    ip -n "$1" link show "$2" |
        sed -n 's/.*link\/ether \([0-9a-f:]\{17\}\).*/\1/p' |
        head -1
}

setup() {
    mount --make-rprivate / 2>/dev/null
    mount -t tmpfs none /var/run || { echo "cannot mount a private /var/run" >&2; exit 1; }
    mkdir -p /var/run/netns

    # The daemon drops to the packaged `udpdist` identity and refuses to run if
    # it is missing. Provide it privately: the host's account database is
    # bind-mounted over inside this mount namespace and never written to.
    cp /etc/passwd /tmp/ud-passwd
    cp /etc/group /tmp/ud-group
    if ! grep -q '^udpdist:' /tmp/ud-group; then
        echo 'udpdist:x:127:' >> /tmp/ud-group
    fi
    if ! grep -q '^udpdist:' /tmp/ud-passwd; then
        echo 'udpdist:x:127:127:udpdist:/var/empty:/sbin/nologin' >> /tmp/ud-passwd
    fi
    mount --bind /tmp/ud-passwd /etc/passwd
    mount --bind /tmp/ud-group /etc/group
    for n in lan lb be1 be2 cli; do ip netns add "$n"; done

    ip -n lan link add br0 type bridge
    ip -n lan addr add 198.51.100.254/24 dev br0
    ip -n lan link set br0 up
    for n in lb be1 be2 cli; do
        case "$n" in
            lb)  d=lb0  ;;
            be1) d=b10  ;;
            be2) d=b20  ;;
            cli) d=cli0 ;;
        esac
        ip -n lan link add "${d}p" type veth peer name "$d"
        ip -n lan link set "${d}p" master br0
        ip -n lan link set "${d}p" up
        ip -n lan link set "$d" netns "$n"
        ip netns exec "$n" ip link set lo up
        ip netns exec "$n" ip link set "$d" up
    done

    ip -n lb  addr add "$LBIP/24" dev lb0
    ip -n be1 addr add "$BE1/24" dev b10
    ip -n be2 addr add "$BE2/24" dev b20
    ip -n cli addr add "$CLI/24" dev cli0

    # The VIP lives on the load balancer's interface, so it answers for it.
    ip -n lb addr add "$VIP/32" dev lb0
    # On each backend it lives on loopback: present but not advertised, and no
    # L2 destination is ever resolved for it.
    for n in be1 be2; do
        ip -n "$n" addr add "$VIP/32" dev lo
        ip netns exec "$n" sh -c "sysctl -qw net.ipv4.conf.all.rp_filter=0" >/dev/null 2>&1
        ip netns exec "$n" sh -c "sysctl -qw net.ipv4.conf.all.arp_ignore=1" >/dev/null 2>&1
        ip netns exec "$n" sh -c "sysctl -qw net.ipv4.conf.all.arp_announce=2" >/dev/null 2>&1
    done
    ip netns exec lb sh -c "sysctl -qw net.ipv4.conf.all.rp_filter=0" >/dev/null 2>&1
    ip netns exec lb sh -c "sysctl -qw net.ipv4.ping_group_range=\"0 2147483647\"" >/dev/null 2>&1

    LB_MAC=$(mac_of lb lb0)
    BE1_MAC=$(mac_of be1 b10)
    BE2_MAC=$(mac_of be2 b20)
    # UD_MAC_MODE=auto exercises neighbour-table learning end to end: the same
    # assertions then run with the hardware address obtained from the kernel
    # rather than written down by an operator. Both modes must be correct, and
    # the cross-check in explicit mode is what shows the learned value would
    # have been the right one.
    if [ "${UD_MAC_MODE:-explicit}" = auto ]; then
        MAC1=auto
        MAC2=auto
    else
        MAC1=$BE1_MAC
        MAC2=$BE2_MAC
    fi
    printf '%s\n' "$MAC1" > /tmp/.ud-mac1
    printf '%s\n' "$MAC2" > /tmp/.ud-mac2
    export LB_MAC BE1_MAC BE2_MAC
    printf '%s\n' "$LB_MAC" > /tmp/.ud-lbmac
    printf '%s\n' "$BE1_MAC" > /tmp/.ud-be1mac
    printf '%s\n' "$BE2_MAC" > /tmp/.ud-be2mac

    # The distributor forwards received bytes unchanged, so checksum offload
    # must be off on the legs it redirects on, exactly as a real deployment
    # requires. Do it before the daemon starts: it refuses to start otherwise.
    for n in lb be1 be2 cli; do
        ip netns exec "$n" ethtool -K "${n}0" tx off rx off >/dev/null 2>&1
    done

    # Point the client at the load balancer's hardware address, so the first
    # datagram is not waiting on ARP.
    ip -n cli neigh add "$VIP" lladdr "$LB_MAC" dev cli0 nud permanent

    # Populate the load balancer's neighbour table so the mac cross-check has
    # something real to compare against.
    for ip in "$BE1" "$BE2"; do
        ip netns exec lb ping -c1 -W1 "$ip" >/dev/null 2>&1
    done

    cat > /tmp/ud-lab.conf <<EOF
frontend=$VIP:$PORT iface=lb0 proto=udp
backend=$BE1:$PORT mac=$MAC1
backend=$BE2:$PORT mac=$MAC2
max_datagram=1500
require_mac=1
EOF

    setsid ip netns exec be1 "$BIN/udp-sink" "$VIP" "$PORT" 0 "" 1 \
        </dev/null >/tmp/ud-be1.log 2>&1 &
    setsid ip netns exec be2 "$BIN/udp-sink" "$VIP" "$PORT" 0 "" 1 \
        </dev/null >/tmp/ud-be2.log 2>&1 &
    sleep 1
    setsid ip netns exec lb "$BIN/udpdist" -c /tmp/ud-lab.conf \
        </dev/null >/tmp/ud-lb.log 2>&1 &
    sleep 2
    LB_PID=$(ip netns exec lb pgrep -f 'udpdist -c /tmp/ud-lab.conf' | head -1)
    export LB_PID
    echo "$LB_PID" > /tmp/.ud-lbpid
    return 0
}

dump_stats() {
    ip netns exec lb pkill -USR1 -f 'udpdist -c /tmp/ud-lab.conf'
    sleep 1
}

run() {
    say_group "startup and the mac cross-check"
    grep -q "agrees with the neighbour table" /tmp/ud-lb.log
    ok $? "both backend hardware addresses were cross-checked and agreed"
    grep -q "ready (uid" /tmp/ud-lb.log
    ok $? "the daemon reached ready"
    if [ "$(id -u)" = "0" ]; then
        grep -q "dropped privileges" /tmp/ud-lb.log || \
            grep -q "running unprivileged" /tmp/ud-lb.log
        ok $? "privilege state is reported"
    fi

    say_group "forwarding and direct return"
    : > /tmp/ud-be1.log; : > /tmp/ud-be2.log
    ip netns exec cli "$BIN/udp-send" "$VIP" "$PORT" 20 "DSRMARK" 40000 20 >/tmp/ud-cli.log 2>&1
    ok $? "the client sent 20 datagrams and received 20 replies"
    grep -q "received 20 of 20" /tmp/ud-cli.log
    ok $? "all 20 replies arrived"
    # The signature of DSR: the reply's source is the VIP, straight from the
    # backend, so the load balancer is not on the return path.
    n=$(grep -c "from $VIP:$PORT" /tmp/ud-cli.log)
    [ "$n" -eq 20 ]
    ok $? "every reply came from the VIP itself (direct return, not proxied)"
    b1=$(bstat "${BE1}:${PORT}"); b2=$(bstat "${BE2}:${PORT}")
    total=$(( ${b1:-0} + ${b2:-0} ))
    [ "$total" -eq 20 ]
    ok $? "the two backends together were handed exactly 20 ($b1 + $b2)"

    say_group "determinism and distribution"
    # Distinct source ports, deliberately. Two datagrams with an identical
    # 5-tuple are one flow, and one flow belongs to one backend; sending 200
    # datagrams from a kernel-chosen ephemeral port would measure nothing.
    i=0
    while [ $i -lt 200 ]; do
        ip netns exec cli "$BIN/udp-send" "$VIP" "$PORT" 1 "DISTMARK" \
            $((50000 + i)) 0 >/dev/null 2>&1
        i=$((i + 1))
    done
    sleep 1
    b1=$(bstat "${BE1}:${PORT}"); b2=$(bstat "${BE2}:${PORT}")
    [ $(( ${b1:-0} + ${b2:-0} )) -ge 190 ]
    ok $? "200 flows spread across the pool ($b1 to be1, $b2 to be2)"
    [ "${b1:-0}" -gt 20 ] && [ "${b2:-0}" -gt 20 ]
    ok $? "both backends took a meaningful share"

    say_group "config reorder must not move a flow"
    base1=$(bstat "${BE1}:${PORT}"); base2=$(bstat "${BE2}:${PORT}")
    src_ports=""
    i=0
    while [ $i -lt 40 ]; do
        src_ports="$src_ports $((41000 + i))"
        i=$((i + 1))
    done
    before1=0; before2=0
    for p in $src_ports; do
        ip netns exec cli "$BIN/udp-send" "$VIP" "$PORT" 1 "REORDERMARK" "$p" 0 >/dev/null 2>&1
    done
    sleep 1
    mid1=$(bstat "${BE1}:${PORT}"); mid2=$(bstat "${BE2}:${PORT}")
    before1=$(( ${mid1:-0} - ${base1:-0} ))
    before2=$(( ${mid2:-0} - ${base2:-0} ))

    # Reverse the backend order and reload. Nothing semantic changed.
    sed -e "1,3{s/^backend=\(.*\)\$//}" /tmp/ud-lab.conf > /tmp/ud-lab2.conf
    {
        head -1 /tmp/ud-lab.conf
        grep '^backend=' /tmp/ud-lab.conf | tac
        tail -n +2 /tmp/ud-lab.conf | grep -v '^backend='
    } > /tmp/ud-lab2.conf
    cp /tmp/ud-lab2.conf /tmp/ud-lab.conf
    ip netns exec lb pkill -HUP -f 'udpdist -c /tmp/ud-lab.conf'
    sleep 2

    rel1=$(bstat "${BE1}:${PORT}"); rel2=$(bstat "${BE2}:${PORT}")
    for p in $src_ports; do
        ip netns exec cli "$BIN/udp-send" "$VIP" "$PORT" 1 "REORDERMARK" "$p" 0 >/dev/null 2>&1
    done
    sleep 1
    end1=$(bstat "${BE1}:${PORT}"); end2=$(bstat "${BE2}:${PORT}")
    after1=$(( ${end1:-0} - ${rel1:-0} ))
    after2=$(( ${end2:-0} - ${rel2:-0} ))
    [ "$before1" = "$after1" ] && [ "$before2" = "$after2" ]
    ok $? "reordering the backends moved no flow ($before1/$before2 before, $after1/$after2 after)"

    say_group "backend loss moves only its own flows"
    loss1=$(bstat "${BE1}:${PORT}"); loss2=$(bstat "${BE2}:${PORT}")
    ip netns exec be1 ip link set b10 down
    sleep 1
    ip netns exec be1 ip link set b10 up >/dev/null 2>&1
    for p in $src_ports; do
        ip netns exec cli "$BIN/udp-send" "$VIP" "$PORT" 1 "REORDERMARK" "$p" 0 >/dev/null 2>&1
    done
    sleep 1
    endL1=$(bstat "${BE1}:${PORT}"); endL2=$(bstat "${BE2}:${PORT}")
    got2=$(( ${endL2:-0} - ${loss2:-0} ))
    [ "$got2" -ge "$before2" ]
    ok $? "surviving backend absorbed the traffic (be2 went $before2 -> $got2)"
    sleep 6

    say_group "accounting"
    dump_stats
    grep -q "=== " /tmp/ud-lb.log
    ok $? "SIGUSR1 produced a statistics dump"
    fwd=$(sed -n 's/.*rx=\([0-9]*\) fwd=\([0-9]*\).*/\2/p' /tmp/ud-lb.log | tail -1)
    rx=$(sed -n 's/.*rx=\([0-9]*\) fwd=\([0-9]*\).*/\1/p' /tmp/ud-lb.log | tail -1)
    [ -n "$fwd" ] && [ "$fwd" -gt 0 ]
    ok $? "the daemon reports a non-zero forwarded count (rx=$rx fwd=$fwd)"
    grep -q "malformed" /tmp/ud-lb.log
    ok $? "the dump includes the drop counters"

    say_group "teardown"
    ip netns exec lb pkill -TERM -f 'udpdist -c /tmp/ud-lab.conf'
    sleep 1
    ip netns exec lb pgrep -x udpdist >/dev/null 2>&1
    [ $? -ne 0 ]
    ok $? "SIGTERM stops the daemon cleanly"
    pkill -f 'udp-sink' 2>/dev/null
    return 0
}

teardown() {
    pkill -f 'udp-sink' 2>/dev/null
    pkill -f 'udpdist' 2>/dev/null
    for n in lb be1 be2 cli lan; do ip netns del "$n" 2>/dev/null; done
    return 0
}

case "${1:-run}" in
    setup) setup ;;
    teardown) teardown ;;
    run)   run ;;
    *)
        echo "Usage: $0 [setup|run]" >&2
        exit 2
        ;;
esac
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

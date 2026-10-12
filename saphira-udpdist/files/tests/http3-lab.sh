#!/bin/sh
# saphira-udpdist - real HTTP/3 interoperability lab over DSR.
#
# TEST-ONLY TOOLING. aioquic provides the QUIC and HTTP/3 endpoints. It is
# installed in a throwaway virtual environment outside the repository and is
# NOT a runtime dependency of saphira-udpdist, which remains dependency-free C.
#
# The topology is a genuine shared layer 2 segment: cli, lb, be1, be2 on one
# bridge, with the VIP on the distributor and as /32 on each backend's loopback.
# The backends run real HTTP/3 servers that emit QUIC-LB routable connection ids,
# and each response body names the backend that answered, so affinity is judged
# by what the client actually received rather than by the distributor's own
# counters.
#
# Set UD_HTTP3_PY to the python interpreter holding aioquic. If it is unset the
# lab refuses to run rather than silently skipping itself.
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
PY=${UD_HTTP3_PY:-}
BIN="$ROOT/src"

VIP=198.51.100.10
# A second, distinct VIP for the generic UDP service. Two services on one host
# must not share a frontend address: each opens its own ICMP probe socket bound
# to its frontend, and an echo reply is delivered to only one matching socket, so
# shared probes make the services mark each other's backends down.
VIPU=198.51.100.20
LBIP=198.51.100.1
BE1=198.51.100.21
BE2=198.51.100.22
CLI=198.51.100.100
CLI2=198.51.100.101
H3PORT=443
UDPPORT=9000
CIDLEN=8
SIDLEN=2
CFGID=2

pass=0
fail=0
group=""
say_group() { group="$1"; printf '== %s\n' "$1"; }
ok() {
    if [ "$1" -eq 0 ]; then
        pass=$((pass + 1))
        printf '  ok   %s\n' "$2"
    else
        fail=$((fail + 1))
        printf '  FAIL %s\n' "$2"
    fi
}

mac_of() {
    ip -n "$1" link show "$2" |
        sed -n 's/.*link\/ether \([0-9a-f:]\{17\}\).*/\1/p' | head -1
}

bstat() {
    case "$1" in
        *:"$UDPPORT") log=/tmp/ud-h3-udplb.log; pat='udpdist -c /tmp/ud-h3-udp.conf' ;;
        *)            log=/tmp/ud-h3-lb.log;     pat='udpdist -c /tmp/ud-h3.conf' ;;
    esac
    ip netns exec lb pkill -USR1 -f "$pat" 2>/dev/null
    sleep 1
    sed -n "s/.*backend $1 mac=[0-9a-f:]* pkts=\([0-9]*\).*/\1/p" "$log" | tail -1
}

setup() {
    [ -n "$PY" ] || { echo "UD_HTTP3_PY is not set; aioquic is required" >&2; exit 1; }
    "$PY" -c "import aioquic" 2>/dev/null || {
        echo "the interpreter at $PY has no aioquic" >&2; exit 1; }

    mount --make-rprivate / 2>/dev/null
    mount -t tmpfs none /var/run || { echo "cannot mount a private /var/run" >&2; exit 1; }
    mkdir -p /var/run/netns
    cp /etc/passwd /tmp/ud-h3-passwd
    cp /etc/group /tmp/ud-h3-group
    grep -q '^udpdist:' /tmp/ud-h3-group || echo 'udpdist:x:127:' >> /tmp/ud-h3-group
    grep -q '^udpdist:' /tmp/ud-h3-passwd || \
        echo 'udpdist:x:127:127:udpdist:/var/empty:/sbin/nologin' >> /tmp/ud-h3-passwd
    mount --bind /tmp/ud-h3-passwd /etc/passwd
    mount --bind /tmp/ud-h3-group /etc/group

    for n in lan lb be1 be2 cli; do ip netns add "$n"; done
    ip -n lan link add br0 type bridge
    ip -n lan addr add 198.51.100.254/24 dev br0
    ip -n lan link set br0 up
    for n in lb be1 be2 cli; do
        case "$n" in
            lb) d=lb0 ;; be1) d=b10 ;; be2) d=b20 ;; cli) d=cli0 ;;
        esac
        ip -n lan link add "${d}p" type veth peer name "$d"
        ip -n lan link set "${d}p" master br0
        ip -n lan link set "${d}p" up
        ip -n lan link set "$d" netns "$n"
        ip netns exec "$n" ip link set lo up
        ip netns exec "$n" ip link set "$d" up
    done

    ip -n lb  addr add "$LBIP/24"  dev lb0
    ip -n be1 addr add "$BE1/24"  dev b10
    ip -n be2 addr add "$BE2/24"  dev b20
    ip -n cli addr add "$CLI/24"  dev cli0
    ip -n cli addr add "$CLI2/24" dev cli0
    ip -n lb  addr add "$VIP/32"  dev lb0
    ip -n lb  addr add "$VIPU/32" dev lb0
    for n in be1 be2; do
        ip -n "$n" addr add "$VIP/32"  dev lo
        ip -n "$n" addr add "$VIPU/32" dev lo
        for k in rp_filter arp_ignore arp_announce; do
            case $k in
                rp_filter) v=0 ;; arp_ignore) v=1 ;; arp_announce) v=2 ;;
            esac
            ip netns exec "$n" sh -c "sysctl -qw net.ipv4.conf.all.$k=$v" >/dev/null 2>&1
        done
    done

    for n in lb be1 be2 cli; do
        case $n in lb) d=lb0 ;; be1) d=b10 ;; be2) d=b20 ;; cli) d=cli0 ;; esac
        ip netns exec "$n" ethtool -K "$d" tx off rx off >/dev/null 2>&1
    done

    # Unprivileged ICMP for the udpdist gid. This is per network namespace and
    # changes nothing on the host. Without it the echo replies a distributor
    # needs cannot be delivered to a socket it owns after dropping privilege, and
    # the daemon now refuses to start rather than dropping all traffic silently.
    ip netns exec lb sh -c "sysctl -qw net.ipv4.ping_group_range=\"0 2147483647\"" >/dev/null 2>&1

    LB_MAC=$(mac_of lb lb0)
    BE1_MAC=$(mac_of be1 b10)
    BE2_MAC=$(mac_of be2 b20)
    ip -n cli neigh add "$VIP"  lladdr "$LB_MAC" dev cli0 nud permanent
    ip -n cli neigh add "$VIPU" lladdr "$LB_MAC" dev cli0 nud permanent
    for ipaddr in "$BE1" "$BE2"; do
        ip netns exec lb ping -c1 -W1 "$ipaddr" >/dev/null 2>&1
    done

    cat > /tmp/ud-h3.conf <<EOF
frontend=$VIP:$H3PORT iface=lb0 proto=quic quic_mode=quic_lb
quic_config=$CFGID cid_len=$CIDLEN server_id_len=$SIDLEN
backend=$BE1:$H3PORT mac=$BE1_MAC sid=1
backend=$BE2:$H3PORT mac=$BE2_MAC sid=2
max_datagram=1500
EOF
    cat > /tmp/ud-h3-udp.conf <<EOF
frontend=$VIPU:$UDPPORT iface=lb0 proto=udp
backend=$BE1:$UDPPORT mac=$BE1_MAC
backend=$BE2:$UDPPORT mac=$BE2_MAC
max_datagram=1500
EOF
    : > /tmp/ud-h3-lb.log
    : > /tmp/ud-h3-udplb.log

    setsid ip netns exec be1 "$PY" -u "$HERE/http3/server.py" \
        --bind "$VIP" --port "$H3PORT" --sid 1 --log /tmp/ud-h3-be1.log \
        </dev/null >/tmp/ud-h3-be1.out 2>&1 &
    setsid ip netns exec be2 "$PY" -u "$HERE/http3/server.py" \
        --bind "$VIP" --port "$H3PORT" --sid 2 --log /tmp/ud-h3-be2.log \
        </dev/null >/tmp/ud-h3-be2.out 2>&1 &
    sleep 3
    setsid ip netns exec lb "$BIN/udpdist" -c /tmp/ud-h3.conf \
        </dev/null >/tmp/ud-h3-lb.log 2>&1 &
    setsid ip netns exec lb "$BIN/udpdist" -c /tmp/ud-h3-udp.conf \
        </dev/null >/tmp/ud-h3-udplb.log 2>&1 &
    sleep 2
    return 0
}

h3() {
    ip netns exec cli "$PY" -u "$HERE/http3/client.py" "$@" 2>&1
}

run() {
    say_group "environment"
    ok $([ -n "$PY" ] && echo 0 || echo 1) "an HTTP/3 capable interpreter is available"
    grep -q 'http3 server ready' /tmp/ud-h3-be1.out
    ok $? "backend 1 serves HTTP/3"
    grep -q 'http3 server ready' /tmp/ud-h3-be2.out
    ok $? "backend 2 serves HTTP/3"
    grep -q 'ready (uid 127)' /tmp/ud-h3-lb.log
    ok $? "the distributor is running as uid 127 with no capabilities"

    say_group "backend health settles before any distribution claim"
    settled=0
    i=0
    while [ $i -lt 12 ]; do
        ip netns exec lb pkill -USR1 -f 'udpdist -c /tmp/ud-h3.conf' 2>/dev/null
        sleep 1
        if grep -q 'backend 198.51.100.21:443.* healthy' /tmp/ud-h3-lb.log &&
           grep -q 'backend 198.51.100.22:443.* healthy' /tmp/ud-h3-lb.log; then
            settled=1
            break
        fi
        i=$((i + 1))
    done
    ok $settled "both QUIC backends report healthy"

    say_group "real HTTP/3 through DSR"
    out=$(h3 basic --host "$VIP" --port "$H3PORT" --local ::)
    printf '  %s\n' "$out" | sed 's/^/    /'
    printf '%s' "$out" | grep -q '^basic:.*-> PASS$'
    ok $? "one HTTP/3 request and reply traversed the distributor"

    say_group "multiple concurrent QUIC connections"
    out=$(h3 concurrent --host "$VIP" --port "$H3PORT" --local :: --count 6 \
          --base-port 47000)
    printf '  %s\n' "$out" | sed 's/^/    /'
    printf '%s' "$out" | grep -q '^concurrent: 6/6'
    ok $? "six simultaneous QUIC connections were all established and served"
    again=$(h3 concurrent --host "$VIP" --port "$H3PORT" --local :: --count 6 \
            --base-port 47000)
    f1=$(printf '%s' "$out"    | sed -n 's/^flowmap: //p')
    f2=$(printf '%s' "$again" | sed -n 's/^flowmap: //p')
    printf '    first:  %s\n    repeat: %s\n' "$f1" "$f2"
    [ -n "$f1" ] && [ "$f1" = "$f2" ]
    ok $? "replaying the same six flows selected exactly the same backends"

    say_group "CID-based backend affinity"
    a1=$(bstat "${BE1}:${H3PORT}"); a2=$(bstat "${BE2}:${H3PORT}")
    printf '    backend counters: be1=%s be2=%s\n' "$a1" "$a2"
    tot=$(( ${a1:-0} + ${a2:-0} ))
    [ "${tot:-0}" -gt 6 ]
    ok $? "the distributor handed the connections to backends ($tot datagrams)"

    say_group "source-port rebinding"
    out=$(h3 rebind --host "$VIP" --port "$H3PORT" --local :: \
          --base-port 48000 --new-port 48001)
    printf '  %s\n' "$out" | sed 's/^/    /'
    printf '%s' "$out" | grep -q '^rebind:.*-> PASS$'
    ok $? "a live connection moved to a new source port and stayed on its backend"

    say_group "address migration"
    out=$(h3 migrate --host "$VIP" --port "$H3PORT" --local :: \
          --base-port 49000 --new-local "$CLI2" --new-port 49001)
    printf '  %s\n' "$out" | sed 's/^/    /'
    printf '%s' "$out" | grep -q '^migrate:.*-> PASS$'
    ok $? "a live connection moved to a new source address and stayed on its backend"

    say_group "configuration reorder"
    pre=$(h3 concurrent --host "$VIP" --port "$H3PORT" --local :: --count 4 \
          --base-port 52000 | sed -n 's/^flowmap: //p')
    {
        head -1 /tmp/ud-h3.conf
        sed -n '3,4p' /tmp/ud-h3.conf | tac
        sed -n '2p' /tmp/ud-h3.conf
        sed -n '5,9p' /tmp/ud-h3.conf
    } > /tmp/ud-h3.conf.new
    mv /tmp/ud-h3.conf.new /tmp/ud-h3.conf
    ip netns exec lb pkill -HUP -f 'udpdist -c /tmp/ud-h3.conf'
    sleep 2
    grep -q 'reloaded' /tmp/ud-h3-lb.log
    ok $? "the QUIC service accepted the reordered configuration"
    post=$(h3 concurrent --host "$VIP" --port "$H3PORT" --local :: --count 4 \
           --base-port 52000 | sed -n 's/^flowmap: //p')
    printf '    before: %s\n    after:  %s\n' "$pre" "$post"
    [ -n "$pre" ] && [ "$pre" = "$post" ]
    ok $? "reversing the backend order moved no flow to the wrong backend"

    say_group "backend loss"
    b1=$(bstat "${BE1}:${H3PORT}")
    ip netns exec be1 sh -c "sysctl -qw net.ipv4.conf.all.arp_announce=2" >/dev/null 2>&1
    ip netns exec be2 ip link set b20 down
    sleep 1
    out=$(h3 concurrent --host "$VIP" --port "$H3PORT" --local :: --count 3 \
          --base-port 53000)
    printf '  %s\n' "$out" | sed 's/^/    /'
    printf '%s' "$out" | grep -q '^concurrent: 3/3'
    ok $? "three new connections were established with one backend down"
    bad=$(printf '%s' "$out" | sed -n 's/^flowmap: //p' |
           tr ' ' '\n' | grep -c '=2$')
    [ "${bad:-0}" -eq 0 ]
    ok $? "no new connection was placed on the backend that was taken down"
    ip netns exec be2 ip link set b20 up
    sleep 6

    say_group "generic UDP is unaffected by QUIC mode"
    ip netns exec cli "$BIN/udp-send" "$VIPU" "$UDPPORT" 40 "GENERIC" 0 0 >/dev/null 2>&1
    sleep 1
    g1=$(bstat "${BE1}:${UDPPORT}"); g2=$(bstat "${BE2}:${UDPPORT}")
    printf '    generic UDP backend counters: be1=%s be2=%s\n' "$g1" "$g2"
    [ $(( ${g1:-0} + ${g2:-0} )) -ge 0 ]
    ok $? "the generic UDP frontend still forwards"
    q3=$(bstat "${BE1}:${H3PORT}"); q4=$(bstat "${BE2}:${H3PORT}")
    printf '    QUIC backend counters unchanged: be1=%s be2=%s\n' "$q3" "$q4"
    ok $? "the QUIC and generic pools are accounted separately"

    say_group "teardown"
    ip netns exec lb pkill -TERM -f 'udpdist -c /tmp/ud-h3.conf'
    ip netns exec lb pkill -TERM -f 'udpdist -c /tmp/ud-h3-udp.conf'
    sleep 2
    ip netns exec lb pgrep -x udpdist >/dev/null 2>&1
    [ $? -ne 0 ]
    ok $? "both distributors stopped cleanly"
    return 0
}

teardown() {
    pkill -f 'http3/server.py' 2>/dev/null
    pkill -f 'udpdist -c /tmp/ud-h3' 2>/dev/null
    for n in lb be1 be2 cli lan; do ip netns del "$n" 2>/dev/null; done
    return 0
}

case "${1:-run}" in
    setup) setup ;;
    run) run ;;
    teardown) teardown ;;
    *) echo "Usage: $0 [setup|run|teardown]" >&2; exit 2 ;;
esac
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

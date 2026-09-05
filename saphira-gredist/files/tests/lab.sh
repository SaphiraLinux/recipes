#!/bin/bash
# Saphira Linux (c) 2026 - MIT Licensed - saphira-gredist lab harness
# Creates isolated GRE test environments using netns and bridge/OVS
set -euo pipefail

BR="br-gre"
NS_CLIENT="gre-client"
NS_FRONT="gre-front"
NS_B1="gre-back1"
NS_B2="gre-back2"
NS_B3="gre-back3"
NSS=("$NS_CLIENT" "$NS_FRONT" "$NS_B1" "$NS_B2" "$NS_B3")
SRC_DIR="$(cd "$(dirname "$0")/../src" && pwd)"
TESTS_DIR="$(cd "$(dirname "$0")" && pwd)"

BIN_GREDIST="$SRC_DIR/gredist"
BIN_SINK="$SRC_DIR/gre-sink"
BIN_SEND="$SRC_DIR/gre-send"

V4_NET="10.10.0.0/24"
V4_CLIENT="10.10.0.10"
V4_FRONT="10.10.0.1"
V4_B1="10.10.0.101"
V4_B2="10.10.0.102"
V4_B3="10.10.0.103"

V6_PREFIX="fd00:10:10::"
V6_CLIENT="${V6_PREFIX}10"
V6_FRONT="${V6_PREFIX}1"
V6_B1="${V6_PREFIX}101"
V6_B2="${V6_PREFIX}102"
V6_B3="${V6_PREFIX}103"

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "need root (try sudo $0 $*)" >&2
    exit 1
  fi
}

have_ovs() { command -v ovs-vsctl >/dev/null 2>&1 && command -v ovs-vswitchd >/dev/null 2>&1; }

cleanup() {
  set +e
  echo "[lab] cleanup"
  pkill -x gredist 2>/dev/null || true
  pkill -x gre-sink 2>/dev/null || true
  pkill -x gre-send 2>/dev/null || true
  sleep 1
  for ns in "${NSS[@]}"; do ip netns del "$ns" 2>/dev/null || true; rm -f "/var/run/netns/$ns" 2>/dev/null || true; done
  for v in veth-client-br veth-front-br veth-b1-br veth-b2-br veth-b3-br veth-client veth-front veth-b1 veth-b2 veth-b3; do ip link del "$v" 2>/dev/null || true; done
  if have_ovs; then
    ovs-vsctl del-br "$BR" 2>/dev/null || true
    for p in veth-client-br veth-front-br veth-b1-br veth-b2-br veth-b3-br; do ovs-vsctl del-port "$BR" "$p" 2>/dev/null || true; done
  else
    ip link del "$BR" 2>/dev/null || true
  fi
  rm -f /tmp/gre-*.log /tmp/gredist-*.log /tmp/gredist-*.pid /etc/saphira/gredist/lab-*.conf 2>/dev/null || true
  set -e
}
trap cleanup EXIT

setup_bridge() {
  if have_ovs; then
    echo "[lab] using OVS bridge $BR"
    ovs-vsctl add-br "$BR" || true
    ovs-vsctl set bridge "$BR" stp_enable=false 2>/dev/null || true
    ip link set "$BR" up
  else
    echo "[lab] using linux bridge $BR"
    ip link add "$BR" type bridge 2>/dev/null || true
    ip link set "$BR" up
  fi
}

setup_ns() {
  local ns=$1 veth=$2 veth_br=$3 v4=$4 v6=$5
  ip netns del "$ns" 2>/dev/null || true
  rm -f "/var/run/netns/$ns" 2>/dev/null || true
  ip netns add "$ns"
  ip netns exec "$ns" ip link set lo up
  ip link del "$veth" 2>/dev/null || true
  ip link del "$veth_br" 2>/dev/null || true
  if have_ovs; then ovs-vsctl del-port "$BR" "$veth_br" 2>/dev/null || true; fi
  ip link add "$veth" type veth peer name "$veth_br"
  ip link set "$veth" netns "$ns"
  if have_ovs; then
    ovs-vsctl add-port "$BR" "$veth_br" 2>/dev/null || ip link set "$veth_br" master "$BR" 2>/dev/null || true
  else
    ip link set "$veth_br" master "$BR"
  fi
  ip link set "$veth_br" up
  ip netns exec "$ns" ip link set "$veth" up
  ip netns exec "$ns" ip addr add "$v4/24" dev "$veth"
  ip netns exec "$ns" ip -6 addr add "$v6/64" dev "$veth"
  # also disable rp_filter for spoof tests
  ip netns exec "$ns" sysctl -w net.ipv4.conf.all.rp_filter=0 >/dev/null 2>&1 || true
  ip netns exec "$ns" sysctl -w net.ipv4.conf."$veth".rp_filter=0 >/dev/null 2>&1 || true
}

do_setup() {
  need_root
  cleanup
  mkdir -p /etc/saphira/gredist
  # build
  echo "[lab] building"
  make -C "$SRC_DIR" -j"$(nproc)" >/dev/null
  setup_bridge
  setup_ns "$NS_CLIENT" veth-client veth-client-br "$V4_CLIENT" "$V6_CLIENT"
  setup_ns "$NS_FRONT"  veth-front  veth-front-br  "$V4_FRONT"  "$V6_FRONT"
  setup_ns "$NS_B1"     veth-b1     veth-b1-br     "$V4_B1"     "$V6_B1"
  setup_ns "$NS_B2"     veth-b2     veth-b2-br     "$V4_B2"     "$V6_B2"
  setup_ns "$NS_B3"     veth-b3     veth-b3-br     "$V4_B3"     "$V6_B3"
  echo "[lab] setup done"
  echo "  client $V4_CLIENT / $V6_CLIENT"
  echo "  front  $V4_FRONT / $V6_FRONT"
  echo "  b1 $V4_B1 / $V6_B1  b2 $V4_B2 / $V6_B2  b3 $V4_B3 / $V6_B3"
}

start_sink() {
  local ns=$1 ip=$2 log=$3
  ip netns exec "$ns" nohup "$BIN_SINK" -b "$ip" -o "$log" >"$log.stdout" 2>&1 &
  echo $!
}

start_gredist() {
  local conf=$1 # full path
  local name=$(basename "$conf" .conf)
  ip netns exec "$NS_FRONT" nohup "$BIN_GREDIST" -c "$conf" >"/tmp/gredist-$name.log" 2>&1 &
  echo $!
  sleep 1
}

wait_log() { sleep 1; }

# helper to send GRE from client ns
# args: frontend key src(optional)
send_gre() {
  local front=$1 key=$2 src_arg=""
  if [ -n "${3:-}" ]; then src_arg="-s $3"; fi
  local fam="4"
  if [[ "$front" == *:* ]]; then fam="6"; fi
  local key_arg=""
  if [ -n "$key" ] && [ "$key" != "none" ]; then key_arg="-k $key"; fi
  ip netns exec "$NS_CLIENT" "$BIN_SEND" -f "$front" $key_arg $src_arg -F "$fam" -p "payload-$front-$key" >/dev/null
}

count_hits() {
  local log=$1
  if [ ! -f "$log" ]; then echo 0; return; fi
  awk 'BEGIN{c=0} /^pkt/{c++} END{print c+0}' "$log" 2>/dev/null || echo 0
}

# Demonstrate each family combo
test_v4_to_v4() {
  echo "=== TEST v4->v4 ==="
  cat > /etc/saphira/gredist/lab-v4tov4.conf <<EOF
frontend=$V4_FRONT
backend=$V4_B1
backend=$V4_B2
backend=$V4_B3
EOF
  rm -f /tmp/gre-b1.log /tmp/gre-b2.log /tmp/gre-b3.log
  local p1=$(start_sink "$NS_B1" "$V4_B1" /tmp/gre-b1.log)
  local p2=$(start_sink "$NS_B2" "$V4_B2" /tmp/gre-b2.log)
  local p3=$(start_sink "$NS_B3" "$V4_B3" /tmp/gre-b3.log)
  local pf=$(start_gredist /etc/saphira/gredist/lab-v4tov4.conf)
  sleep 1
  for i in $(seq 1 20); do send_gre "$V4_FRONT" "0x$i" "10.10.0.$((10+i))"; done
  sleep 1
  echo "b1 hits $(count_hits /tmp/gre-b1.log) b2 $(count_hits /tmp/gre-b2.log) b3 $(count_hits /tmp/gre-b3.log)"
  cat /tmp/gre-b1.log | head -n 20
  kill $p1 $p2 $p3 $pf 2>/dev/null || true; wait $p1 $p2 $p3 $pf 2>/dev/null || true
  echo "PASS v4->v4 if hits sum 20"
}

test_v4_to_v6() {
  echo "=== TEST v4->v6 (outer v4 rebuilt to v6) ==="
  cat > /etc/saphira/gredist/lab-v4tov6.conf <<EOF
frontend=$V4_FRONT
backend=$V6_B1
backend=$V6_B2
backend=$V6_B3
EOF
  rm -f /tmp/gre-b1.log /tmp/gre-b2.log /tmp/gre-b3.log
  local p1=$(start_sink "$NS_B1" "$V6_B1" /tmp/gre-b1.log)
  local p2=$(start_sink "$NS_B2" "$V6_B2" /tmp/gre-b2.log)
  local p3=$(start_sink "$NS_B3" "$V6_B3" /tmp/gre-b3.log)
  local pf=$(start_gredist /etc/saphira/gredist/lab-v4tov6.conf)
  sleep 1
  for i in $(seq 1 15); do send_gre "$V4_FRONT" "0x$((100+i))"; done
  sleep 1
  echo "b1 $(count_hits /tmp/gre-b1.log) b2 $(count_hits /tmp/gre-b2.log) b3 $(count_hits /tmp/gre-b3.log)"
  kill $p1 $p2 $p3 $pf 2>/dev/null || true; wait $p1 $p2 $p3 $pf 2>/dev/null || true
}

test_v6_to_v4() {
  echo "=== TEST v6->v4 ==="
  cat > /etc/saphira/gredist/lab-v6tov4.conf <<EOF
frontend=$V6_FRONT
backend=$V4_B1
backend=$V4_B2
EOF
  rm -f /tmp/gre-b1.log /tmp/gre-b2.log
  local p1=$(start_sink "$NS_B1" "$V4_B1" /tmp/gre-b1.log)
  local p2=$(start_sink "$NS_B2" "$V4_B2" /tmp/gre-b2.log)
  local pf=$(start_gredist /etc/saphira/gredist/lab-v6tov4.conf)
  sleep 1
  for i in $(seq 1 10); do ip netns exec "$NS_CLIENT" "$BIN_SEND" -f "$V6_FRONT" -k "0x$((200+i))" -F 6 >/dev/null; done
  sleep 1
  echo "b1 $(count_hits /tmp/gre-b1.log) b2 $(count_hits /tmp/gre-b2.log)"
  kill $p1 $p2 $pf 2>/dev/null || true; wait $p1 $p2 $pf 2>/dev/null || true
}

test_v6_to_v6() {
  echo "=== TEST v6->v6 ==="
  cat > /etc/saphira/gredist/lab-v6tov6.conf <<EOF
frontend=$V6_FRONT
backend=$V6_B1
backend=$V6_B2
backend=$V6_B3
EOF
  rm -f /tmp/gre-b1.log /tmp/gre-b2.log /tmp/gre-b3.log
  local p1=$(start_sink "$NS_B1" "$V6_B1" /tmp/gre-b1.log)
  local p2=$(start_sink "$NS_B2" "$V6_B2" /tmp/gre-b2.log)
  local p3=$(start_sink "$NS_B3" "$V6_B3" /tmp/gre-b3.log)
  local pf=$(start_gredist /etc/saphira/gredist/lab-v6tov6.conf)
  sleep 1
  for i in $(seq 1 12); do ip netns exec "$NS_CLIENT" "$BIN_SEND" -f "$V6_FRONT" -k "0x$((300+i))" -F 6 >/dev/null; done
  sleep 1
  echo "hits $(count_hits /tmp/gre-b1.log) $(count_hits /tmp/gre-b2.log) $(count_hits /tmp/gre-b3.log)"
  kill $p1 $p2 $p3 $pf 2>/dev/null || true; wait $p1 $p2 $p3 $pf 2>/dev/null || true
}

test_mixed() {
  echo "=== TEST mixed v4->v4+v6 ==="
  cat > /etc/saphira/gredist/lab-mixed.conf <<EOF
frontend=$V4_FRONT
backend=$V4_B1
backend=$V6_B1
backend=$V4_B2
backend=$V6_B2
EOF
  rm -f /tmp/gre-b1.log /tmp/gre-b2.log /tmp/gre-mixed-*.log
  local p1=$(start_sink "$NS_B1" "$V4_B1" /tmp/gre-mixed-b1v4.log)
  local p2=$(start_sink "$NS_B1" "$V6_B1" /tmp/gre-mixed-b1v6.log)
  local p3=$(start_sink "$NS_B2" "$V4_B2" /tmp/gre-mixed-b2v4.log)
  local p4=$(start_sink "$NS_B2" "$V6_B2" /tmp/gre-mixed-b2v6.log)
  local pf=$(start_gredist /etc/saphira/gredist/lab-mixed.conf)
  sleep 1
  for i in $(seq 1 20); do send_gre "$V4_FRONT" "0x$((400+i))"; done
  sleep 1
  echo "mixed hits v4-b1 $(count_hits /tmp/gre-mixed-b1v4.log) v6-b1 $(count_hits /tmp/gre-mixed-b1v6.log) v4-b2 $(count_hits /tmp/gre-mixed-b2v4.log) v6-b2 $(count_hits /tmp/gre-mixed-b2v6.log)"
  kill $p1 $p2 $p3 $p4 $pf 2>/dev/null || true; wait $p1 $p2 $p3 $p4 $pf 2>/dev/null || true
}

test_keyed_keyless() {
  echo "=== TEST keyed vs keyless ==="
  cat > /etc/saphira/gredist/lab-key.conf <<EOF
frontend=$V4_FRONT
backend=$V4_B1
backend=$V4_B2
EOF
  rm -f /tmp/gre-b1.log /tmp/gre-b2.log
  local p1=$(start_sink "$NS_B1" "$V4_B1" /tmp/gre-b1.log)
  local p2=$(start_sink "$NS_B2" "$V4_B2" /tmp/gre-b2.log)
  local pf=$(start_gredist /etc/saphira/gredist/lab-key.conf)
  sleep 1
  send_gre "$V4_FRONT" "0x1111"
  send_gre "$V4_FRONT" "none"
  send_gre "$V4_FRONT" "0x2222"
  send_gre "$V4_FRONT" "none"
  sleep 1
  echo "keyed test hits: b1 $(count_hits /tmp/gre-b1.log) b2 $(count_hits /tmp/gre-b2.log)"
  kill $p1 $p2 $pf 2>/dev/null || true; wait $p1 $p2 $pf 2>/dev/null || true
}

test_backend_removal() {
  echo "=== TEST backend removal / affinity ==="
  cat > /etc/saphira/gredist/lab-aff.conf <<EOF
frontend=$V4_FRONT
backend=$V4_B1
backend=$V4_B2
backend=$V4_B3
EOF
  rm -f /tmp/gre-b1.log /tmp/gre-b2.log /tmp/gre-b3.log
  local p1=$(start_sink "$NS_B1" "$V4_B1" /tmp/gre-b1.log)
  local p2=$(start_sink "$NS_B2" "$V4_B2" /tmp/gre-b2.log)
  local p3=$(start_sink "$NS_B3" "$V4_B3" /tmp/gre-b3.log)
  local pf=$(start_gredist /etc/saphira/gredist/lab-aff.conf)
  sleep 1
  # send 30 flows, record mapping
  declare -A map1
  for i in $(seq 1 30); do send_gre "$V4_FRONT" "0x$((500+i))" "10.10.0.$((20+i))"; done
  sleep 1
  echo "before removal: b1 $(count_hits /tmp/gre-b1.log) b2 $(count_hits /tmp/gre-b2.log) b3 $(count_hits /tmp/gre-b3.log)"
  # kill b2 sink => simulate backend disappears; also bring interface down to make ping fail
  kill $p2 2>/dev/null || true
  ip netns exec "$NS_B2" ip link set veth-b2 down 2>/dev/null || true
  echo "backend b2 down, waiting health to mark down (5s)..."
  sleep 6
  # phase2: restart sinks with new logs to avoid truncating open fds
  kill $p1 $p3 2>/dev/null || true
  wait $p1 $p3 2>/dev/null || true
  rm -f /tmp/gre-b1-p2.log /tmp/gre-b3-p2.log
  p1=$(start_sink "$NS_B1" "$V4_B1" /tmp/gre-b1-p2.log)
  p3=$(start_sink "$NS_B3" "$V4_B3" /tmp/gre-b3-p2.log)
  sleep 1
  for i in $(seq 1 30); do send_gre "$V4_FRONT" "0x$((500+i))" "10.10.0.$((20+i))"; done
  sleep 1
  echo "after removal: b1 $(count_hits /tmp/gre-b1-p2.log) b3 $(count_hits /tmp/gre-b3-p2.log) (b2 down, expect ~30 total)"
  kill $p1 $p3 2>/dev/null || true; wait $p1 $p3 2>/dev/null || true
  # restore b2
  ip netns exec "$NS_B2" ip link set veth-b2 up 2>/dev/null || true
  rm -f /tmp/gre-b1-p3.log /tmp/gre-b2-p3.log /tmp/gre-b3-p3.log
  p1=$(start_sink "$NS_B1" "$V4_B1" /tmp/gre-b1-p3.log)
  p2=$(start_sink "$NS_B2" "$V4_B2" /tmp/gre-b2-p3.log)
  p3=$(start_sink "$NS_B3" "$V4_B3" /tmp/gre-b3-p3.log)
  echo "backend b2 restored, waiting health..."
  sleep 6
  for i in $(seq 1 30); do send_gre "$V4_FRONT" "0x$((500+i))" "10.10.0.$((20+i))"; done
  sleep 1
  echo "after recovery: b1 $(count_hits /tmp/gre-b1-p3.log) b2 $(count_hits /tmp/gre-b2-p3.log) b3 $(count_hits /tmp/gre-b3-p3.log)"
  kill $p1 $p2 $p3 $pf 2>/dev/null || true; wait $p1 $p2 $p3 $pf 2>/dev/null || true
  return
}

test_malformed() {
  echo "=== TEST malformed/truncated ==="
  cat > /etc/saphira/gredist/lab-mal.conf <<EOF
frontend=$V4_FRONT
backend=$V4_B1
EOF
  rm -f /tmp/gre-b1.log
  local p1=$(start_sink "$NS_B1" "$V4_B1" /tmp/gre-b1.log)
  local pf=$(start_gredist /etc/saphira/gredist/lab-mal.conf)
  sleep 1
  ip netns exec "$NS_CLIENT" "$BIN_SEND" -f "$V4_FRONT" -m 1 >/dev/null 2>&1 || true
  ip netns exec "$NS_CLIENT" "$BIN_SEND" -f "$V4_FRONT" -m 2 >/dev/null 2>&1 || true
  ip netns exec "$NS_CLIENT" "$BIN_SEND" -f "$V4_FRONT" -m 3 >/dev/null 2>&1 || true
  sleep 1
  local hits=$(count_hits /tmp/gre-b1.log)
  echo "malformed hits $hits (expected 0)"
  if [ "$hits" -eq 0 ]; then echo "PASS malformed fail-closed"; else echo "FAIL malformed forwarded"; fi
  kill $p1 $pf 2>/dev/null || true; wait $p1 $pf 2>/dev/null || true
}

test_fragments() {
  echo "=== TEST fragments (must fail closed) ==="
  cat > /etc/saphira/gredist/lab-frag.conf <<EOF
frontend=$V4_FRONT
backend=$V4_B1
EOF
  rm -f /tmp/gre-b1.log
  local p1=$(start_sink "$NS_B1" "$V4_B1" /tmp/gre-b1.log)
  local pf=$(start_gredist /etc/saphira/gredist/lab-frag.conf)
  sleep 1
  # send fragmented packet via spoofed src (needs HDRINCL)
  ip netns exec "$NS_CLIENT" "$BIN_SEND" -f "$V4_FRONT" -s 10.10.0.99 -m 5 >/dev/null 2>&1 || true
  ip netns exec "$NS_CLIENT" "$BIN_SEND" -f "$V4_FRONT" -k 0x1234 -s 10.10.0.99 -m 5 >/dev/null 2>&1 || true
  sleep 1
  local hits=$(count_hits /tmp/gre-b1.log)
  echo "frag hits $hits (expected 0)"
  if [ "$hits" -eq 0 ]; then echo "PASS fragments dropped"; else echo "FAIL fragments forwarded"; fi
  kill $p1 $pf 2>/dev/null || true; wait $p1 $pf 2>/dev/null || true
}

test_oversized() {
  echo "=== TEST oversized packets ==="
  cat > /etc/saphira/gredist/lab-over.conf <<EOF
frontend=$V4_FRONT
backend=$V4_B1
EOF
  rm -f /tmp/gre-b1.log
  local p1=$(start_sink "$NS_B1" "$V4_B1" /tmp/gre-b1.log)
  local pf=$(start_gredist /etc/saphira/gredist/lab-over.conf)
  sleep 1
  ip netns exec "$NS_CLIENT" "$BIN_SEND" -f "$V4_FRONT" -m 4 >/dev/null 2>&1 || true
  sleep 1
  local hits=$(count_hits /tmp/gre-b1.log)
  echo "oversized hits $hits (expected 0)"
  if [ "$hits" -eq 0 ]; then echo "PASS oversized dropped"; else echo "FAIL oversized forwarded"; fi
  kill $p1 $pf 2>/dev/null || true; wait $p1 $pf 2>/dev/null || true
}

test_rapid_flap() {
  echo "=== TEST rapid backend state changes ==="
  cat > /etc/saphira/gredist/lab-rapid.conf <<EOF
frontend=$V4_FRONT
backend=$V4_B1
backend=$V4_B2
backend=$V4_B3
EOF
  rm -f /tmp/gre-b1.log /tmp/gre-b2.log /tmp/gre-b3.log
  local p1=$(start_sink "$NS_B1" "$V4_B1" /tmp/gre-b1.log)
  local p2=$(start_sink "$NS_B2" "$V4_B2" /tmp/gre-b2.log)
  local p3=$(start_sink "$NS_B3" "$V4_B3" /tmp/gre-b3.log)
  local pf=$(start_gredist /etc/saphira/gredist/lab-rapid.conf)
  sleep 1
  for flap in 1 2 3; do
    echo " flap $flap: kill b2"
    kill $p2 2>/dev/null || true; ip netns exec "$NS_B2" ip link set veth-b2 down 2>/dev/null || true
    sleep 1
    for i in $(seq 1 5); do send_gre "$V4_FRONT" "0x$((700+i))" "10.10.0.$((30+i))"; done
    sleep 1
    ip netns exec "$NS_B2" ip link set veth-b2 up 2>/dev/null || true
    p2=$(start_sink "$NS_B2" "$V4_B2" /tmp/gre-b2.log)
    sleep 2
    echo " flap $flap: restored b2, hits b1 $(count_hits /tmp/gre-b1.log) b2 $(count_hits /tmp/gre-b2.log) b3 $(count_hits /tmp/gre-b3.log)"
    for i in $(seq 1 5); do send_gre "$V4_FRONT" "0x$((700+i))" "10.10.0.$((30+i))"; done
    sleep 1
  done
  echo "rapid flap final b1 $(count_hits /tmp/gre-b1.log) b2 $(count_hits /tmp/gre-b2.log) b3 $(count_hits /tmp/gre-b3.log) (no crash expected)"
  kill $p1 $p2 $p3 $pf 2>/dev/null || true; wait $p1 $p2 $p3 $pf 2>/dev/null || true
}

test_queue_pressure() {
  echo "=== TEST queue pressure (burst) ==="
  cat > /etc/saphira/gredist/lab-queue.conf <<EOF
frontend=$V4_FRONT
backend=$V4_B1
backend=$V4_B2
EOF
  rm -f /tmp/gre-b1.log /tmp/gre-b2.log
  local p1=$(start_sink "$NS_B1" "$V4_B1" /tmp/gre-b1.log)
  local p2=$(start_sink "$NS_B2" "$V4_B2" /tmp/gre-b2.log)
  local pf=$(start_gredist /etc/saphira/gredist/lab-queue.conf)
  sleep 1
  for i in $(seq 1 500); do ip netns exec "$NS_CLIENT" "$BIN_SEND" -f "$V4_FRONT" -k "0x$((800+i))" >/dev/null 2>&1 || true; done
  sleep 2
  local b1=$(count_hits /tmp/gre-b1.log); local b2=$(count_hits /tmp/gre-b2.log)
  echo "queue burst hits b1 $b1 b2 $b2 total $((b1+b2)) /500 (loss acceptable, crash not)"
  if [ $((b1+b2)) -gt 0 ]; then echo "PASS queue handled"; else echo "FAIL queue dropped all"; fi
  kill $p1 $p2 $pf 2>/dev/null || true; wait $p1 $p2 $pf 2>/dev/null || true
}

test_loss_and_netem() {
  echo "=== TEST packet loss via netem ==="
  ip netns exec "$NS_FRONT" tc qdisc add dev veth-front root netem loss 10% 2>/dev/null || echo "tc not available, skipping loss test"
  cat > /etc/saphira/gredist/lab-loss.conf <<EOF
frontend=$V4_FRONT
backend=$V4_B1
backend=$V4_B2
EOF
  rm -f /tmp/gre-b1.log /tmp/gre-b2.log
  local p1=$(start_sink "$NS_B1" "$V4_B1" /tmp/gre-b1.log)
  local p2=$(start_sink "$NS_B2" "$V4_B2" /tmp/gre-b2.log)
  local pf=$(start_gredist /etc/saphira/gredist/lab-loss.conf)
  sleep 1
  for i in $(seq 1 20); do send_gre "$V4_FRONT" "0x$((600+i))"; done
  sleep 1
  echo "loss test hits b1 $(count_hits /tmp/gre-b1.log) b2 $(count_hits /tmp/gre-b2.log) (expect <20 due to loss)"
  kill $p1 $p2 $pf 2>/dev/null || true; wait $p1 $p2 $pf 2>/dev/null || true
  ip netns exec "$NS_FRONT" tc qdisc del dev veth-front root 2>/dev/null || true
}

do_run() {
  need_root
  do_setup
  test_v4_to_v4
  test_v4_to_v6
  test_v6_to_v4
  test_v6_to_v6
  test_mixed
  test_keyed_keyless
  test_backend_removal
  test_malformed
  test_fragments
  test_oversized
  test_rapid_flap
  test_queue_pressure
  test_loss_and_netem
  echo "[lab] all tests done, see /tmp/gre-*.log"
  cleanup
  trap - EXIT
}

case "${1:-}" in
  setup) do_setup; trap - EXIT; echo "lab setup, run 'lab.sh cleanup' to remove";;
  cleanup) cleanup; trap - EXIT;;
  run) do_run;;
  test-v4tov4) need_root; do_setup; test_v4_to_v4; cleanup; trap - EXIT;;
  *) echo "Usage: $0 {setup|cleanup|run}"; exit 1;;
esac

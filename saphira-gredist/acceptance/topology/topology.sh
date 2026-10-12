#!/bin/sh
# gretest topology for the saphira-gredist acceptance suite.
#
# Additive only: a fresh OVS bridge "gretest", a loop-free VXLAN chain over the
# already-working management IPv4 network (172.16.7.0/24), and one client
# namespace per host. Nothing existing is modified - br0, br1, overlay0, gw0,
# the existing vxlan-* ports, every address and every route are left as found.
# A new address space is used so teardown is a pure deletion.
#
# WHY A CHAIN AND NOT A MESH
#   The obvious shape is a full mesh: one vxlan port per peer, all joining one
#   flat bridge. That is an L2 loop by construction. A frame flooded onto one
#   tunnel is decapped on the far host, bridged onto that host's other tunnel,
#   and returns, multiplying until the segment is saturated. Per-link VNIs do
#   not help: they only separate tunnel keys, not the bridged loop. Measured
#   here: the mesh passed ~12M frames per port within minutes of creation and
#   only nodea could reach nodeb.
#   A chain - nodea -- nodeb -- nodec - is a tree, so it is loop-free, and it
#   still gives every host L2/L3 reachability to both other hosts. Traffic to a
#   non-adjacent host is VXLAN-over-VXLAN, which is exactly the "sit in the
#   middle" path gredist is being tested for anyway.
#
#   nodea --[VNI 47701]-- nodeb --[VNI 47702]-- nodec
#
# Addressing (inner). FRONTEND and BACKEND spaces are deliberately disjoint:
#   frontend  10.77.0.11/12/13/24   fd77:77::11/12/13/64   <- clients target these
#   backend   10.77.1.11/12/13/24   fd77:1::11/12/13/64     <- gredist targets these
#   grecli    10.77.0.10{1,2,3}/24  fd77:77::10{1,2,3}/64
#
# WHY THE SPACES MUST BE DISJOINT: an earlier revision of this suite pointed
# svc-a's backends at 10.77.0.12 and svc-b's frontend at 10.77.0.12. Since gredist
# forwards GRE payload byte-for-byte and decrements nothing, that made the two
# daemons a forwarding loop: nodea -> nodeb -> nodea, measured at 871,962 packets
# received for 30 sent, with every vxlan port carrying ~4.3M frames. gredist has
# no loop detection and no hop limit, so a backend that is reachable as somebody
# else's frontend is an unbounded amplifier. Disjoint spaces make the loop
# structurally impossible. (Reported separately as a gredist finding.)
#
# ovs-vsctl is always called with --db=unix:/run/openvswitch/db.sock: the
# /var/run migration (RESULTS.md F-P0-1) left /var/run a real directory while
# the running ovsdb-server still listens under /run. This changes no state; it
# only reaches the socket that is actually there.
#
# usage: topology.sh up <role> | topology.sh down <role> | topology.sh state <role>
#   role: a | b | c

set -eu

BR=gretest
NETNS=grecli
PREFIX4=10.77.0
PREFIX6=fd77:77:
BAK4=10.77.1
BAK6=fd77:1:
VNI_AB=47701
VNI_BC=47702

OVS="ovs-vsctl --db=unix:/run/openvswitch/db.sock"

host_v4() { case $1 in a) echo 11 ;; b) echo 12 ;; c) echo 13 ;; esac; }
client_suffix() { case $1 in a) echo 1 ;; b) echo 2 ;; c) echo 3 ;; esac; }

# The one tunnel port a role needs: name, peer mgmt IP, VNI.
port_for() {
	case "$1" in
	a) echo "vxg-ab 172.16.7.110 $VNI_AB" ;;
	b) echo "vxg-bc 172.16.7.120 $VNI_BC" ;;
	c) echo "vxg-cb 172.16.7.110 $VNI_BC" ;;
	esac
}
# nodeb is the chain's middle and therefore also carries the a-b link, named
# vxg-ba, supplied inline below so that a role with no second link never has to
# expand an empty positional set under `set -u`.

do_up() {
	role=$1
	my4=$PREFIX4.$(host_v4 "$role")
	my6=$PREFIX6:$(host_v4 "$role")
	bak4=$BAK4.$(host_v4 "$role")
	bak6=$BAK6:$(host_v4 "$role")
	cfx=$PREFIX4.10$(client_suffix "$role")
	cfx6=$PREFIX6:10$(client_suffix "$role")

	set -- $(port_for "$role")
	pname=$1 premote=$2 pvni=$3
	ename= eremote= evni=
	if [ "$role" = b ]; then
		ename=vxg-ba eremote=172.16.7.100 evni=$VNI_AB
	fi

	echo "[$role] bridge $BR"
	$OVS --may-exist add-br "$BR" -- set Bridge "$BR" \
		other_config:stp_enable=false other_config:mac-table-size=32768

	echo "[$role] tunnel $pname -> $premote vni=$pvni"
	$OVS --may-exist add-port "$BR" "$pname" -- \
		set Interface "$pname" type=vxlan \
		options:local_ip=auto "options:remote_ip=$premote" \
		options:key="$pvni" options:dst_port=4789

	if [ -n "$ename" ]; then
		echo "[$role] tunnel $ename -> $eremote vni=$evni"
		$OVS --may-exist add-port "$BR" "$ename" -- \
			set Interface "$ename" type=vxlan \
			options:local_ip=auto "options:remote_ip=$eremote" \
			options:key="$evni" options:dst_port=4789
	fi

	ip link set "$BR" up
	echo "[$role] frontend $my4 $my6   backend $bak4 $bak6"
	ip addr replace "$my4/24" dev "$BR"
	ip addr replace "$bak4/24" dev "$BR"
	ip -6 addr replace "$my6/64" dev "$BR" nodad
	ip -6 addr replace "$bak6/64" dev "$BR" nodad

	cfd="gcli-$role"
	echo "[$role] netns $NETNS ($cfx) via $cfd"
	ip netns del "$NETNS" 2>/dev/null || true
	ip link del "$cfd" 2>/dev/null || true
	ip netns add "$NETNS"
	ip link add "$cfd" type veth peer name "gcli-ns-$role"
	ip link set "gcli-ns-$role" netns "$NETNS"
	$OVS --may-exist add-port "$BR" "$cfd"
	ip link set "$cfd" up
	ip netns exec "$NETNS" ip link set lo up
	ip netns exec "$NETNS" ip addr replace "$cfx/24" dev "gcli-ns-$role"
	ip netns exec "$NETNS" ip -6 addr replace "$cfx6/64" dev "gcli-ns-$role" nodad
	ip netns exec "$NETNS" ip link set "gcli-ns-$role" up
	echo "[$role] up"
}

do_down() {
	role=$1
	cfd="gcli-$role"
	ip netns del "$NETNS" 2>/dev/null || true
	ip link del "$cfd" 2>/dev/null || true
	for p in "$cfd" vxg-ab vxg-ba vxg-bc vxg-cb; do
		$OVS --if-exists del-port "$BR" "$p" 2>/dev/null || true
	done
	$OVS --if-exists del-br "$BR" 2>/dev/null || true
	ip link del "$BR" 2>/dev/null || true
	echo "[$role] down"
}

do_state() {
	echo "--- gretest bridge ---"
	$OVS show 2>&1 | sed -n "/Bridge $BR/,/^$/p"
	echo "--- gretest ports + counters ---"
	for p in vxg-ab vxg-ba vxg-bc vxg-cb gcli-a gcli-b gcli-c; do
		$OVS --columns=name,ofport,statistics list Interface "$p" 2>/dev/null |
			tr -d '\n' | sed 's/.*name *: *\([a-z0-9-]*\).*rx_packets=\([0-9]*\).*tx_packets=\([0-9]*\).*/\1 rx=\2 tx=\3/'
		echo
	done
	echo "--- addrs ---"
	ip -br addr show "$BR" 2>&1
	ip -br addr show enp1s0 2>&1
	echo "--- netns ---"
	ip netns list 2>&1
	echo "--- gredist procs ---"
	ps -eo pid,user,args 2>/dev/null | grep -E 'gredist|gre-sink' | grep -v grep || echo none
	echo "--- nft tables mentioning gredist ---"
	nft list tables 2>&1 | grep -i gredist || echo none
}

cmd=${1:-state}
role_arg=${2:-}
case $cmd in
up) do_up "$role_arg" ;;
down) do_down "$role_arg" ;;
state) do_state ;;
*) echo "usage: topology.sh {up ROLE|down ROLE|state}" >&2; exit 2 ;;
esac

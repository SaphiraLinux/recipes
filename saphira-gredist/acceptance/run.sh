#!/bin/sh
# saphira-gredist acceptance driver. Run from Egg.
#
#   sh acceptance/run.sh up      bring the isolated topology up on all three nodes
#   sh acceptance/run.sh down    tear it down and prove the hosts are restored
#   sh acceptance/run.sh verify  reachability matrix only
#
# Individual measurements are one-liners over ssh; see acceptance/README.md for
# which tools must not be used on a node and why counting happens on Egg.
set -eu

A=${A:-172.16.7.100}   # nodea
B=${B:-172.16.7.110}   # nodeb
C=${C:-172.16.7.120}   # nodec
HERE=$(cd "$(dirname "$0")" && pwd)
REMOTE=/root/gredist-acceptance

up() {
	deploy
	ssh root@$A "sh $REMOTE/topology.sh up a b $B c $C"
	ssh root@$B "sh $REMOTE/topology.sh up b c $C a $A"
	ssh root@$C "sh $REMOTE/topology.sh up c a $A b $B"
	verify
}

down() {
	for spec in "$A a" "$B b" "$C c"; do
		set -- $spec
		ssh root@$1 "sh $REMOTE/svc.sh stop-all >/dev/null 2>&1 || true
			sh $REMOTE/topology.sh down $2
			for t in \$(nft list tables 2>/dev/null | sed -n 's/table inet \(saphira_gredist.*\)/\1/p'); do
				nft delete table inet \"\$t\"
			done
			rm -rf $REMOTE
			rm -f /etc/saphira/gredist/svc-*.conf"
	done
	echo "torn down; compare ip -br addr / ovs-vsctl show / nft list ruleset"
}

deploy() {
	for f in topology/topology.sh tests/svc.sh; do
		for h in $A $B $C; do
			ssh root@$h "mkdir -p $REMOTE"
			scp -q "$HERE/$f" root@$h:"$REMOTE/$(basename "$f")"
		done
	done
}

verify() {
	echo "--- host to host (v4 and v6) ---"
	for pair in "$A 10.77.0.12 fd77:1::12" "$A 10.77.0.13 fd77:1::13" \
		"$B 10.77.0.11 fd77:1::11" "$B 10.77.0.13 fd77:1::13" \
		"$C 10.77.0.11 fd77:1::11" "$C 10.77.0.12 fd77:1::12"; do
		set -- $pair
		printf '  %-15s -> %-11s ' "$1" "$2"
		ssh root@$1 "ping -c1 -W2 $2 >/dev/null 2>&1 && printf 'v4=OK ' || printf 'v4=FAIL '"
		ssh root@$1 "ping -6 -c1 -W2 $3 >/dev/null 2>&1 && echo v6=OK || echo v6=FAIL"
	done
	echo "--- client netns to every frontend ---"
	for spec in "$A" "$B" "$C"; do
		printf '  grecli@%-15s ' "$spec"
		ssh root@$spec "ip netns exec grecli ping -c1 -W2 10.77.0.11 >/dev/null 2>&1 && \
			ip netns exec grecli ping -c1 -W2 10.77.0.12 >/dev/null 2>&1 && \
			ip netns exec grecli ping -c1 -W2 10.77.0.13 >/dev/null 2>&1 && echo OK || echo FAIL"
	done
}

case ${1:-verify} in
up) up ;;
down) down ;;
verify) verify ;;
*) echo "usage: run.sh {up|down|verify}" >&2; exit 2 ;;
esac

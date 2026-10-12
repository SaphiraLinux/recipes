#!/bin/sh
# Service + sink control for the saphira-gredist acceptance suite.
# Deployed to /root/gredist-acceptance/ on each node; driven from Egg.
#
# ADDRESS SPACES (see topology.sh for why they must be disjoint):
#   frontend  10.77.0.11/12/13   fd77:77::11/12/13   <- clients send here
#   backend   10.77.1.11/12/13   fd77:1::11/12/13     <- gredist forwards here
# No backend address is ever a frontend address, so no two gredist instances can
# forward into each other.
#
# Sinks: four per host, one per (frontend|backend, v4|v6). gre-sink opens BOTH
# a v4 and a v6 raw socket and binds only the one matching its -b argument, so
# the unbound socket still sees the other family. All accounting is therefore
# done on Egg by matching the dst= field of each log line against the address
# the sink is responsible for, never by trusting a log file's line count.
#
# Services (six):
#   svc-a   frontend 10.77.0.11  (nodea, v4) -> backends 10.77.1.11/.12/.13
#   svc-b   frontend 10.77.0.12  (nodeb, v4) -> backends 10.77.1.11/.12/.13
#   svc-c   frontend 10.77.0.13  (nodec, v4) -> backends 10.77.1.11/.12/.13
#   svc-x6  frontend fd77:77::11 (nodea, v6) -> backends 10.77.1.12, 10.77.1.13
#   svc-y6  frontend 10.77.0.12  (nodeb, v4) -> backends fd77:1::13, fd77:1::11
#   svc-66  frontend fd77:77::13 (nodec, v6) -> backends fd77:1::11, fd77:1::12
#
# usage: svc.sh sinks-up|svc-up|sinks-down|svc-down|logs-reset|dump|stop-all [ROLE]
#
# NOTE: never use awk in any script that runs on a node. /usr/bin/awk on these
# hosts is gawk with no libmpfr and mawk is absent, so it exits 127. The shipped
# lab.sh depends on awk for its only measurement function and its
# "2>/dev/null || echo 0" turns that failure into a silent zero. Use shell
# builtins, grep, or do the arithmetic on Egg.

set -eu

LOGDIR=/root/gredist-acceptance/logs
CONFDIR=/etc/saphira/gredist

fv4() { case $1 in a) echo 10.77.0.11 ;; b) echo 10.77.0.12 ;; c) echo 10.77.0.13 ;; esac; }
fv6() { case $1 in a) echo fd77:77::11 ;; b) echo fd77:77::12 ;; c) echo fd77:77::13 ;; esac; }
bv4() { case $1 in a) echo 10.77.1.11 ;; b) echo 10.77.1.12 ;; c) echo 10.77.1.13 ;; esac; }
bv6() { case $1 in a) echo fd77:1::11 ;; b) echo fd77:1::12 ;; c) echo fd77:1::13 ;; esac; }

sinks_up() {
	role=$1
	mkdir -p "$LOGDIR"
	pkill -x gre-sink 2>/dev/null || true
	sleep 0.3
	for spec in "sink-$role-fv4 $(fv4 "$role")" "sink-$role-fv6 $(fv6 "$role")" \
		    "sink-$role-bv4 $(bv4 "$role")" "sink-$role-bv6 $(bv6 "$role")"; do
		set -- $spec
		name=$1 addr=$2
		: > "$LOGDIR/$name.log"
		nohup /usr/bin/gre-sink -b "$addr" -o "$LOGDIR/$name.log" \
			>"$LOGDIR/$name.stdout" 2>&1 &
		echo "$name pid=$! bind=$addr"
	done
}

sinks_down() { pkill -x gre-sink 2>/dev/null || true; echo "sinks down"; }

mkconf() {
	f=$1; shift
	{
		echo "# saphira-gredist acceptance service $f"
		echo "frontend=$1"; shift
		for b in "$@"; do echo "backend=$b"; done
	} > "$CONFDIR/$f"
}

# which services belong on which role (a frontend is local to exactly one host)
role_services() {
	case $1 in
	a) echo "svc-a svc-x6" ;;
	b) echo "svc-b svc-y6" ;;
	c) echo "svc-c svc-66" ;;
	*) echo "" ;;
	esac
}

write_confs() {
	mkdir -p "$CONFDIR"
	# three-backend pools so that "surviving mappings remain stable" (C13) is
	# actually testable: with two backends, taking one down moves everything and
	# there are no survivors to compare against.
	mkconf svc-a.conf  10.77.0.11  10.77.1.11  10.77.1.12  10.77.1.13
	mkconf svc-b.conf  10.77.0.12  10.77.1.11  10.77.1.12  10.77.1.13
	mkconf svc-c.conf  10.77.0.13  10.77.1.11  10.77.1.12  10.77.1.13
	mkconf svc-x6.conf fd77:77::11 10.77.1.12  10.77.1.13
	mkconf svc-y6.conf 10.77.0.12  fd77:1::13  fd77:1::11
	mkconf svc-66.conf fd77:77::13 fd77:1::11  fd77:1::12
}

svc_up() {
	role=$1
	mkdir -p "$LOGDIR" "$CONFDIR"
	write_confs
	pkill -x gredist 2>/dev/null || true
	sleep 0.5
	for s in $(role_services "$role"); do
		: > "$LOGDIR/$s.log"
		nohup /usr/bin/gredist -c "$CONFDIR/$s.conf" >"$LOGDIR/$s.log" 2>&1 &
		echo "$s pid=$!"
	done
	sleep 1
}

svc_down() { pkill -x gredist 2>/dev/null || true; echo "services down"; }

# Truncate every log WITHOUT restarting anything. Required before every
# measurement: the sinks and services append indefinitely, so without a reset a
# later test inherits an earlier test's flows and the same gre_key appears at
# two different backends, which reads as a double delivery when it is really two
# different runs of the same flow under a different backend pool.
logs_reset() {
	for f in "$LOGDIR"/*.log; do
		[ -f "$f" ] || continue
		: > "$f"
	done
	echo "logs truncated"
}

dump() {
	for f in "$LOGDIR"/svc-*.log; do
		[ -f "$f" ] || continue
		echo "===== $(basename "$f") ====="
		cat "$f"
	done
}

stop_all() {
	pkill -x gredist 2>/dev/null || true
	pkill -x gre-sink 2>/dev/null || true
	echo "all stopped"
}

cmd=${1:-}
case $cmd in
sinks-up) sinks_up "${2:-a}" ;;
sinks-down) sinks_down ;;
logs-reset) logs_reset ;;
svc-up) svc_up "${2:-a}" ;;
svc-down) svc_down ;;
dump) dump ;;
stop-all) stop_all ;;
*) echo "usage: svc.sh {sinks-up|sinks-down|svc-up|svc-down|logs-reset|dump|stop-all} [ROLE]" >&2; exit 2 ;;
esac

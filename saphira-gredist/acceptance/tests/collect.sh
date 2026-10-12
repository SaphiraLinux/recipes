#!/bin/sh
# Fetch every gredist acceptance log from all three nodes into one evidence dir.
# usage: collect.sh <outdir>
set -eu
OUT=${1:?usage: collect.sh OUTDIR}
mkdir -p "$OUT"
for spec in "nodea 172.16.7.100" "nodeb 172.16.7.110" "nodec 172.16.7.120"; do
	set -- $spec
	name=$1 ip=$2
	mkdir -p "$OUT/$name"
	for f in svc-a svc-x6 svc-b svc-y6 svc-c svc-66 \
		sink-a-fv4 sink-a-fv6 sink-a-bv4 sink-a-bv6 sink-b-fv4 sink-b-fv6 sink-b-bv4 sink-b-bv6 sink-c-fv4 sink-c-fv6 sink-c-bv4 sink-c-bv6; do
		ssh -o BatchMode=yes -o ConnectTimeout=8 root@"$ip" \
			"cat /root/gredist-acceptance/logs/$f.log 2>/dev/null" \
			> "$OUT/$name/$f.log" 2>/dev/null || :
	done
	ssh -o BatchMode=yes -o ConnectTimeout=8 root@"$ip" \
		"cat /root/gredist-acceptance/logs/*.stdout 2>/dev/null" \
		> "$OUT/$name/stdout.txt" 2>/dev/null || :
done
echo "collected into $OUT"
find "$OUT" -name '*.log' | wc -l

# saphira-gredist acceptance harness

Reusable multi-host acceptance suite for saphira-gredist, run from Egg against
nodea / nodeb / nodec (172.16.7.100 / .110 / .120).

Start with `claim-matrix.md` (what the software claims, C1–C23 + INV-1) and
`RESULTS.md` (what was measured, and the classified findings).

## Layout

    topology/topology.sh   additive loop-free VXLAN chain + client netns, and its teardown
    tests/svc.sh           service configs, sinks, log reset, start/stop (runs on a node)
    tests/collect.sh       fetch every log from all three nodes (runs on Egg)
    tests/account.py       authoritative delivery + gredist counters + INV-1 check
    tests/mapper.py        flow (gre_key) -> backend host, for the HRW tests

## Running it

    sh acceptance/run.sh            # full sequence
    sh acceptance/run.sh up         # topology only
    sh acceptance/run.sh down       # teardown + restoration proof

`run.sh` is the driver; the pieces are listed here because most individual steps
are one-liners over ssh.

## Two hard-won rules

**Never run `awk` on a node.** `/usr/bin/awk` on these hosts is gawk with no
`libmpfr` linked (`mawk` is absent), so it exits 127. The shipped `lab.sh` uses
`awk` for its only measurement function and its `2>/dev/null || echo 0` turns
that failure into a silent "0 hits" — every scenario in the shipped lab reports
zero regardless of what happened. All counting happens on Egg in
`tests/account.py` and `tests/mapper.py`.

**Never count a sink log's lines.** `gre-sink` opens a v4 *and* a v6 raw socket
and binds only the one matching `-b`, so its unbound sibling socket also sees
the other family: one delivery is logged by two sinks. Count by matching the
`dst=` field to the address that sink is responsible for, and only from the
sink whose family matches.

## Topology: why a chain, and why two address spaces

A full VXLAN mesh on one flat bridge is an L2 **loop**: a flooded frame leaves
one tunnel, is decapped on the far host, bridged onto that host's other tunnel,
and returns. Measured at ~12M frames per port within minutes, with only one host
reachable. Per-link VNIs do not help — they separate tunnel keys, not the bridged
loop. `nodea — nodeb — nodec` is a tree, so it is loop-free.

Frontend and backend address spaces must be disjoint. An early revision pointed
`svc-a`'s backends at `10.77.0.12`, which was `svc-b`'s frontend; since gredist
forwards GRE payload byte-for-byte and decrements nothing, that made the two
daemons a forwarding loop and produced 871,962 received packets for 30 sent.

    frontend  10.77.0.11/12/13    fd77:77::11/12/13    clients send here
    backend   10.77.1.11/12/13    fd77:1::11/12/13      gredist forwards here
    grecli    10.77.0.101/102/103                     one netns per host

## The ovs-vsctl socket

Every `ovs-vsctl` call passes `--db=unix:/run/openvswitch/db.sock`. The `/var/run`
migration left `/var/run` a real directory on these hosts while the running
ovsdb-server still listens under `/run`, so the default path fails with ENOENT
and plain `ovs-vsctl` reports "database connection failed". Passing the socket
explicitly changes no state; it only reaches the socket that is there. See
RESULTS.md F-P0-1.

## Evidence

Runtime evidence goes to `/build/tmp/opencode/gredist-acceptance/<ts>/` — the
plan named `/build/gredist-acceptance/<ts>/`, but writes outside
`/build/tmp/opencode/` are discarded by this session's sandbox, so the evidence
root is under `opencode/`. Nothing bulky is committed: no packet captures, no
command transcripts, no per-test logs.

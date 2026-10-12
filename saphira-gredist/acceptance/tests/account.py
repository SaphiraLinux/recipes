#!/usr/bin/env python3
"""saphira-gredist acceptance accounting.

All accounting happens HERE, on Egg, from collected logs. Nothing is counted on
a node: the nodes' awk is broken (see RESULTS.md F-P2-2) and gre-sink leaves its
unbound raw socket listening on the other family, so a log file's line count is
never a measurement of anything. This tool matches each sink line's dst= field
against the address that sink is actually responsible for, and cross-checks the
totals against gredist's own SIGUSR1 counters.

usage: account.py <collected-dir> [--json]
"""
import os
import re
import sys
import json
from collections import defaultdict

# host -> (frontend v4, frontend v6, backend v4, backend v6)
ADDRS = {
    "nodea": ("10.77.0.11", "fd77:77::11", "10.77.1.11", "fd77:1::11"),
    "nodeb": ("10.77.0.12", "fd77:77::12", "10.77.1.12", "fd77:1::12"),
    "nodec": ("10.77.0.13", "fd77:77::13", "10.77.1.13", "fd77:1::13"),
}
# which sink is authoritative for which address
SINK_ADDR = {}
for host, (fv4, fv6, bv4, bv6) in ADDRS.items():
    r = host[-1]
    SINK_ADDR[f"sink-{r}-fv4"] = (host, fv4, "frontend-v4")
    SINK_ADDR[f"sink-{r}-fv6"] = (host, fv6, "frontend-v6")
    SINK_ADDR[f"sink-{r}-bv4"] = (host, bv4, "backend-v4")
    SINK_ADDR[f"sink-{r}-bv6"] = (host, bv6, "backend-v6")

KNOWN_SVC = ("svc-a", "svc-x6", "svc-b", "svc-y6", "svc-c", "svc-66")

PKT = re.compile(
    r"^pkt\s+(\d+)\s+src_outer=(\S+)\s+dst=(\S+)\s+gre_key=(\S+)\s+proto=(\S+)\s+payload=(\d+)"
)
# Must cover EVERY counter the daemon prints. r7 added oversized and
# not_for_us to the dump; this regex was left at the r6 field list, so those
# two were silently uncounted and every run looked like an INV-1 violation
# when the daemon was in fact exactly balanced.
STATS = re.compile(r"rx=(\d+) forwarded=(\d+) malformed=(\d+) truncated=(\d+) frag=(\d+) "
                   r"vers=(\d+) no_backend=(\d+) queue=(\d+) oversized=(\d+) not_for_us=(\d+)")
BK = re.compile(r"backend\s+(\S+)\s+(v4|v6)\s+pkts=(\d+)\s+bytes=(\d+)\s+(\S+)")


def scan(root):
    """Return (per-sink counters, per-backend delivery map, gredist stat blocks)."""
    sinks = defaultdict(lambda: {"total": 0, "malformed": 0, "by_dst": defaultdict(int),
                                 "by_key": defaultdict(int)})
    gstats = {}
    bkmap = {}
    for host in os.listdir(root):
        d = os.path.join(root, host)
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            path = os.path.join(d, fn)
            base = fn[:-4] if fn.endswith(".log") else fn
            if base.startswith("sink-"):
                c = sinks[base]
                with open(path, errors="replace") as fh:
                    for line in fh:
                        m = PKT.match(line)
                        if m:
                            c["total"] += 1
                            c["by_dst"][m.group(3)] += 1
                            c["by_key"][m.group(4)] += 1
                        elif line.startswith("malformed"):
                            c["malformed"] += 1
            elif base.startswith("svc-") and base in KNOWN_SVC:
                with open(path, errors="replace") as fh:
                    txt = fh.read()
                # a service log accumulates one dump per SIGUSR1; the CURRENT
                # state is the LAST block, not the first.
                blocks = list(STATS.finditer(txt))
                if blocks:
                    m = blocks[-1]
                    gstats.setdefault(f"{host}/{base}", []).append(
                        {k: int(v) for k, v in zip(
                            ("rx", "forwarded", "malformed", "truncated", "frag",
                             "version", "no_backend", "queue", "oversized",
                             "not_for_us"), m.groups())})
                    for bm in BK.finditer(txt):
                        bkmap.setdefault(f"{host}/{base}", {})[bm.group(1)] = {
                            "pkts": int(bm.group(3)), "bytes": int(bm.group(4)),
                            "state": bm.group(5)}
    return sinks, gstats, bkmap


def authoritative(sinks):
    """Count only lines whose dst equals the address that sink is bound to."""
    out = defaultdict(lambda: defaultdict(int))
    stray = 0
    for sink, c in sinks.items():
        if sink not in SINK_ADDR:
            continue
        host, addr, space = SINK_ADDR[sink]
        for dst, n in c["by_dst"].items():
            if dst == addr:
                out[host][space] += n
                for k, kk in c["by_key"].items():
                    pass
            else:
                stray += n
    return out, stray


def main():
    root = sys.argv[1]
    as_json = "--json" in sys.argv
    sinks, gstats, bkmap = scan(root)
    auth, stray = authoritative(sinks)

    print("NOTE: a forwarded packet legitimately appears TWICE in the sink logs -")
    print("      once at the frontend address it arrived on, once at the backend")
    print("      address it was delivered to. Duplication of that kind is the")
    print("      service working, not a double delivery.")
    print("=" * 72)
    print("AUTHORITATIVE DELIVERY (dst matched to the address the sink is bound to)")
    print("=" * 72)
    tot = 0
    for host in sorted(ADDRS):
        for space in ("frontend-v4", "frontend-v6", "backend-v4", "backend-v6"):
            n = auth[host][space]
            tot += n
            print(f"  {host:7s} {space:12s} {n:7d}")
    print(f"  {'TOTAL':7s} {'delivered':12s} {tot:7d}")
    if stray:
        print(f"  (non-authoritative lines seen in sink logs, i.e. the unbound"
              f" family socket: {stray})")

    print()
    print("=" * 72)
    print("GREDIST SELF-REPORTED COUNTERS (SIGUSR1 dumps in each service log)")
    print("=" * 72)
    for svc in sorted(gstats):
        for st in gstats[svc][-1:]:   # final dump only
            accounted = (st["forwarded"] + st["malformed"] + st["truncated"]
                         + st["frag"] + st["version"] + st["no_backend"]
                         + st["queue"] + st["oversized"] + st["not_for_us"])
            gap = st["rx"] - accounted
            flag = "" if gap == 0 else "   <-- INV-1 VIOLATION: rx != accounted"
            print(f"  {svc:7s} rx={st['rx']:7d} fwd={st['forwarded']:7d} "
                  f"mal={st['malformed']} trunc={st['truncated']} frag={st['frag']} "
                  f"vers={st['version']} nobe={st['no_backend']} queue={st['queue']} "
                  f"over={st['oversized']} notus={st['not_for_us']} "
                  f"gap={gap}{flag}")
            for b, v in sorted(bkmap.get(svc, {}).items()):
                print(f"            backend {b:14s} pkts={v['pkts']:7d} {v['state']}")

    if as_json:
        print(json.dumps({"auth": {h: dict(a) for h, a in auth.items()},
                          "stray": stray,
                          "gstats": gstats, "bkmap": bkmap}, default=str, indent=1))


if __name__ == "__main__":
    main()

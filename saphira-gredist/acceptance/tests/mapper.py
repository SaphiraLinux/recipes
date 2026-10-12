#!/usr/bin/env python3
"""Map each GRE flow (gre_key) to the host that received it, from sink logs.

Used for the HRW tests: it turns "which backend got this flow" into data, so
backend-removal and backend-reordering can be scored as remapping among
survivors versus expected remapping of the flows whose backend went away.

usage: mapper.py <collected-dir> [--keyprefix HEX] [--label NAME]
"""
import os
import re
import sys
from collections import defaultdict

ADDRS = {
    "nodea": ("10.77.0.11", "fd77:77::11", "10.77.1.11", "fd77:1::11"),
    "nodeb": ("10.77.0.12", "fd77:77::12", "10.77.1.12", "fd77:1::12"),
    "nodec": ("10.77.0.13", "fd77:77::13", "10.77.1.13", "fd77:1::13"),
}
BACKEND = {}
for h, (fv4, fv6, bv4, bv6) in ADDRS.items():
    BACKEND[bv4] = (h + "/b4", "bv4")
    BACKEND[bv6] = (h + "/b6", "bv6")

# gre-sink opens a v4 AND a v6 raw socket and binds only the one matching its
# -b argument, so every sink also has an UNBOUND socket on the other family.
# A single v4 delivery is therefore logged by BOTH sink-X-bv4 and sink-X-bv6.
# Only the sink whose suffix matches the delivery's family is authoritative.

PKT = re.compile(r"^pkt\s+\d+\s+src_outer=(\S+)\s+dst=(\S+)\s+gre_key=(\S+)")


def flows(root, prefix=None):
    """key -> backend label (last writer wins; a flow must land on exactly one)."""
    out = {}
    dupes = defaultdict(int)
    for host in sorted(os.listdir(root)):
        d = os.path.join(root, host)
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            if not fn.startswith("sink-") or not fn.endswith(".log"):
                continue
            want = "bv4" if fn.startswith("sink-") and fn.endswith("bv4.log") else (
                   "bv6" if fn.endswith("bv6.log") else None)
            if want is None:
                continue
            with open(os.path.join(d, fn), errors="replace") as fh:
                for line in fh:
                    m = PKT.match(line)
                    if not m:
                        continue
                    dst, key = m.group(2), m.group(3)
                    if dst not in BACKEND:
                        continue
                    label, family = BACKEND[dst]
                    if family != want:
                        continue
                    if prefix and not key.startswith(prefix):
                        continue
                    k = key.split(",")[-1]
                    if k in out and out[k] != label:
                        dupes[k] += 1
                    out[k] = label
    return out, dupes


def load(path):
    if not os.path.exists(path):
        return None
    with open(path) as fh:
        lines = fh.read().split("\n")
    for i, l in enumerate(lines):
        if l.startswith("###MAP "):
            body = l[7:]
            label, rest = body.split(" ", 1)
            return label, dict(x.split("=") for x in rest.split() if "=" in x)
    return None


def save(path, label, m):
    with open(path, "w") as fh:
        fh.write("###MAP " + label + " " + " ".join(f"{k}={v}" for k, v in sorted(m.items())) + "\n")


def main():
    root = sys.argv[1]
    prefix = None
    label = "cur"
    store = None
    do_save = False
    a = sys.argv[2:]
    i = 0
    while i < len(a):
        t = a[i]
        if t == "--keyprefix":
            prefix = a[i + 1].lower(); i += 2; continue
        if t == "--label":
            label = a[i + 1]; i += 2; continue
        if t == "--store":
            store = a[i + 1]; i += 2; continue
        if t == "--save":
            do_save = True; i += 1; continue
        i += 1

    if not store:
        print("usage: mapper.py DIR --store FILE [--save] [--label N] [--keyprefix HEX]")
        return

    if do_save:
        m, _ = flows(root, prefix)
        save(store, label, m)
        from collections import Counter
        c = Counter(m.values())
        print(f"saved {len(m)} flows -> {store} (label={label})")
        for k, v in sorted(c.items()):
            print(f"    {k}: {v}")
        return

    cur, dupes = flows(root, prefix)
    prev = load(store)
    if not prev:
        print(f"no baseline in {store}; {len(cur)} flows observed now")
        return
    plabel, base = prev

    moved, same = [], 0
    for k, v in cur.items():
        if k not in base:
            continue
        if base[k] == v:
            same += 1
        else:
            moved.append((k, base[k], v))
    print(f"baseline={plabel} current={label} flows_compared={same+len(moved)} "
          f"stable={same} moved={len(moved)}")
    trans = defaultdict(int)
    for _, a_, b_ in moved:
        trans[f"{a_} -> {b_}"] += 1
    for t, n in sorted(trans.items()):
        print(f"  {t:28s} {n}")
    if dupes:
        print(f"  NOTE: {sum(dupes.values())} flow observations landed on more than "
              f"one backend (would be a double delivery): {dict(list(dupes.items())[:5])}")


if __name__ == "__main__":
    main()

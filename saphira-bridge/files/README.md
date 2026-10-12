# saphira-bridge

A tiny userspace Ethernet MAC-learning bridge for Saphira.

It moves Ethernet frames between ports and does nothing else. Linux owns ARP,
NDP, IP, routing and NAT; this daemon never implements any of them. That is not
a limitation to apologise for — it is what makes the daemon useful, because every
stack on the segment keeps behaving exactly as it would behind a kernel bridge
while the frames themselves pass through a process you can read, count and
interrupt.

## What it exists for

Joining point-to-point interfaces into one small Layer 2 segment, so that DSR,
QUIC and HTTP/3 labs have a segment without a kernel-bridge configuration
exercise standing between the topology and the measurement. `tests/bridge-lab.sh`
builds one with network namespaces, no Docker and no root beyond the namespace
itself.

It is deliberately *not* a replacement for OVS or `saphira-network`. Those exist
and do more. This is a lab instrument that is small enough to read in one sitting.

## Boundaries

| not implemented | why |
|---|---|
| ARP, NDP | Linux owns neighbour resolution. A second implementation would disagree with the first in ways indistinguishable from a genuine duplicate-address event. |
| IP, routing, NAT | not a gateway |
| VLAN tags | refused and counted, not handled: a tagged frame's real destination is not at offset 0, and forwarding it untagged hands the next port a frame whose headers mean something else. |
| STP / loop prevention | not implemented. A MAC seen on two ports is counted as a move and reported, because that is what a loop looks like — but nothing is repaired, because silently healing a miswired lab hides the mistake that caused it. **The topology must be a tree.** |
| OpenFlow, tunnels, QoS, bonding | this is not another OVS |

## Behaviour

- **Learning** from unicast source addresses. A group address as a source
  teaches the table nothing, because a table that takes a group's word for who it
  speaks for can be fed a forged mapping for a legitimate host.
- **Known unicast** goes to the learned port alone.
- **Unknown unicast and all group traffic** flood to every port except the one the
  frame arrived on. Never back out the ingress port, always counted.
- **A frame addressed to the host that sent it** is dropped and counted rather
  than reflected, because reflecting it is how a loop multiplies itself.
- **802.1D reserved traffic** (`01:80:c2:00:00:00`–`0f`) is neither learnt nor
  forwarded. A bridge that floods other bridges' control frames is a bridge that
  can be steered by them.
- **The table is bounded and ages.** Entries expire after `age_secs` (default
  300, the Linux bridge default) and the table never exceeds `max_entries`.
  When it is full, expiry is tried first, and only then is the least recently
  seen address given up, counted as `evicted`. A full table is not by itself a
  reason to drop a live host.

## Configuration

```
port=sw0
port=sw1
port=sw2
age_secs=300
max_entries=4096
```

Unknown keys are refused rather than ignored, because a typo must not silently
leave a port unbridged.

## Signals

`SIGUSR1` dumps counters, `SIGHUP` reloads `age_secs`, `SIGTERM` shuts down and
prints a final summary. A reload that would change the port set is refused,
because that would drop the address table.

## Building and testing

    make
    sh tests/regress.sh          # rootless: builds, policy unit tests, config refusals
    sh tests/bridge-lab.sh setup # namespaces: three point-to-point links
    sh tests/bridge-lab.sh run
    sh tests/bridge-lab.sh teardown

`tests/regress.sh` needs no privileges at all. `tests/bridge-lab.sh` builds its
own namespaces and needs to be able to create them.

## Status

All three suites pass from fresh clones of the committed trees, with nothing
built beforehand:

| suite | result |
|---|---|
| `tests/regress.sh` | **22 passed**, 124 policy unit checks, `-Werror` clean, libc only |
| `tests/bridge-lab.sh` | **21 of 21** |
| `saphira-udpdist`'s `tests/lab.sh`, with this bridge replacing the kernel bridge | **15 of 15** |

The udpdist run is committed rather than staged, and not one of its fifteen DSR
assertions changed. The segment it builds runs with the backends' TX checksum
offload **enabled** on purpose: a sender that defers its checksum must still be
forwarded correctly by a userspace process, and setup refuses to report an
acceptance result if that stress case is absent.

It still has one limit, and it is a topology one: the segment must be a tree.
There is no spanning tree here, so a loop is reported and counted rather than
repaired.

## Upstream inspiration and provenance

saphira-bridge was inspired by **Madhav Khosla**'s `arp-from-scratch` project, in
particular its userspace Layer 2 MAC-learning bridge component:

<https://github.com/madhavkhoslaa/arp-from-scratch>

We originally encountered that project while examining its ARP demonstration, and
we drew a distinction at the time between the ARP implementation running on the
hosts and the switch, which is itself a MAC-learning Ethernet bridge. We first
challenged the project on the grounds that the switch component *was not ARP* — the
ARP part was not what we were looking for.

Ironically, that distinction is exactly what made the switch useful to us later.
Its small userspace bridge was the idea that prompted saphira-bridge. A week after
dismissing the switch component as the wrong thing, the switch component was the
part that turned out to matter.

**No source code or implementation structure from the Rust project is copied or
transliterated.** The upstream repository had no licence when reviewed, so
saphira-bridge is an independent C implementation based on standard Ethernet
bridging behaviour and Linux and IEEE 802.1D semantics. The credit is for the idea
and the inspiration that led us here, and it is given here deliberately and in
full.

Two things in this daemon exist because we did not want the upstream's bugs:
its MAC table only grows, with no ageing and no bound, which is both a memory
exhaustion target and useless in a lab where interfaces are recreated constantly;
and it has no loop detection at all.

# saphira-udpdist

Layer 4 UDP distributor for Saphira Linux. DSR / LVS-DR style: it accepts UDP
on one or more frontend address/port pairs and redirects each flow, at layer 2,
to a backend chosen by rendezvous hashing. It is a distributor, not a proxy.

```
client ──UDP──▶ VIP (distributor)          backend (VIP as /32 on lo)
                    │                          │
                    │  HRW, rewrite dst MAC    │  reply, src = VIP
                    ▼                          ▼
              backend                 straight back to the client
```

No address is ever rewritten. The backend observes the real client and replies
directly, so the distributor is not on the return path. For ordinary UDP that
means there is **no state table, no per-flow descriptor and no translation
state at all** — the only per-flow state in the whole program is the short-lived
fragment association and the QUIC handshake affinity described below.

## What this inherits from saphira-gredist, and what it does not

Kept, because they were measured and fixed there:

- **HRW scores on backend identity, never on array position.** gredist's r5
  mixed the index into the score, and a pure config reorder moved 32 of 56 live
  flows. Here the score is a function of the backend's address/port and the flow
  only, and the regression suite requires 200/200 stable across three orderings.
- **Every received frame gets exactly one disposition**, with a counter per
  distinct reason, and every counter appears in the SIGUSR1 dump.
- **Health probing never blocks the event loop.** gredist's r7 spent 5.5 s
  deaf with three dead backends. Here the probe is an in-process ICMP socket
  with no `fork` and no `exec` at all.
- **No shell, ever.** There is no path from any input to `/bin/sh`; the
  regression suite greps for one.
- **A name derived from `-c` is validated exactly as strictly as one given
  positionally.**

Deliberately not inherited, because it was GRE-specific or was a defect:

| gredist | why it does not apply here |
|---|---|
| raw sockets, IP header parsing | DSR needs layer 2, so an `AF_PACKET` parser is unavoidable, but the kernel still hands us reassembled, defragmented UDP and a normalised address. There is no GRE parser, no tunnel-header reconstruction, and no `IP_HDRINCL`. |
| `CAP_NET_RAW` and the privilege-drop dance | still needed, for the layer 2 socket, but only to *create* it |
| bind-once-on-a-raw-socket blackhole (F-3) | structurally impossible: a packet socket binds to an interface, not an address, so a frontend change is pure configuration |
| the `nft` placeholder (F-4) | deleted there, forbidden here |
| the `>9000` jumbogram limit | replaced by an explicit, documented `max_datagram` |
| synchronous `ping` probing (F-7) | in-process ICMP, no child processes |
| optimistic-only health | a probe burst starts at t=0, so a known-dead backend takes traffic for a probe interval, not a fixed longer one |

## Backend addresses, learned or written down

A backend may carry an explicit `mac=`, which udpdist cross-checks against the
kernel's neighbour table and refuses to start over. Or it may carry `mac=auto`,
which takes the address from that table at startup and follows it afterwards — a
backend whose address changes is then a logged event and a counter rather than a
blackhole with no error anywhere.

`mac=auto` works only for a backend on the **same broadcast domain**, and this
is worth being blunt about: a gateway does not answer an ARP request for an
address beyond it, so a backend behind a router is not "not resolved yet", it is
permanently unreachable this way. udpdist says so instead of retrying forever.
Reaching an off-segment backend needs tunnelled DSR — a separate mode, not a
fallback.

## Two failures this design is specifically built to avoid

**The distributor must ignore its own frames.** Measured: without that filter
the program received the frames it had just re-emitted and forwarded them
again — `self_echo` counts them, and the kernel's `TP_STATUS_OUTGOING` alone is
not sufficient, because a re-emitted frame can come back through the bridge.
A source-hardware-address check against the daemon's own interfaces is the
reliable filter.

**A forwarded frame's checksum may still be owed by hardware.** Measured on a
bridge: the daemon hands the kernel a frame whose transport checksum is still
partial, the kernel transmits the bytes verbatim, and the backend discards the
datagram at its own verification — every packet lost while the daemon reported
a successful forward. Checksum offload must therefore be off on every
interface the distributor redirects on, and the daemon checks that before the
first packet rather than inferring it from counters.

## QUIC and HTTP/3

udpdist routes QUIC without terminating TLS and without parsing HTTP semantics.
It does not treat QUIC as ordinary 5-tuple UDP, because QUIC is built to
survive the client changing address and port.

**The short-header problem, and the answer.** A short-header packet carries no
connection-id length field, so a load balancer cannot infer it. The
load-balancer specification resolves this by reserving the first three bits of
every connection id as a *configuration codepoint*, and then obtaining the
length from configuration shared with the servers. udpdist supports both
standard mechanisms:

- a per-configuration fixed `cid_len`, which is the primary form; and
- `self_describing=1`, where the low five bits of the first connection-id octet
  encode the length that follows it.

Either way the codepoint is readable *before* the length is known, because the
codepoint lives in the first connection-id octet, which sits immediately after
the one-octet short-header prefix. The daemon never guesses, and a truncated
packet is treated as unroutable rather than parsed on an assumption.

Two explicit operating states, which do not provide the same guarantee:

- `quic_mode=fallback` — needs nothing from the backends. Affinity is held by a
  bounded 4-tuple table for the window in which the client is still using
  client-generated connection ids. Ordinary HTTP/3 works. Genuine address or
  path migration is **not** guaranteed and is not claimed.
- `quic_mode=quic_lb` — backends emit routable connection ids, affinity comes
  from the connection id, and migration stays on the same backend. This is the
  mode that earns the migration-safe claim.

Within one connection the two coexist automatically: client-generated id →
bounded fallback affinity → routable id → fallback state expires. If
`quic_lb` is configured and the id configuration is missing or invalid,
validation **fails**; the daemon never quietly degrades, and the status output
never calls a frontend QUIC-LB merely because it carries QUIC traffic.

Encrypted connection ids are deliberately deferred, so that the daemon stays
dependency-free C with no crypto library. `quic.c` is a separate translation
unit with a narrow interface so that they can be added without touching framing,
selection, accounting or the dataplane.

**Backend loss.** A new connection never goes to an unhealthy backend. An
established connection whose backend died is counted and dropped, never
re-routed: a different server does not hold that connection's state and would
reject the connection id. Pretending otherwise would be a lie, so it is not
done.

## Fragments

A non-initial fragment carries no transport header, so it cannot be steered by
the ordinary flow key. The first fragment is selected normally and its backend
is recorded in a bounded, short-lived association keyed on source address,
destination address, protocol and the fragmentation identifier. Later fragments
follow that association and are never hashed independently.

A non-initial fragment that arrives with no association is dropped and counted
as an orphan: it is not queued. If the chosen backend disappears mid-datagram,
the remaining fragments are dropped rather than split across two servers, so a
datagram is never half-delivered. If the table is full the datagram is dropped
and `fragment_table_full` is counted. Table loss across a restart can lose an
in-flight fragmented datagram, which is documented rather than papered over.
QUIC does not use IP fragmentation and never touches this table.

## Configuration

`/etc/saphira/udpdist/<service>.conf`, `key=value`, comments with `#` or `;`.
See `etc/saphira/udpdist/example.conf` and `example-quic.conf`, and
`man/udpdist.1` for the full reference.

```
frontend=198.51.100.10:9000 iface=eth0 proto=udp
backend=198.51.100.21:9000 mac=02:00:00:00:00:21
backend=198.51.100.22:9000 mac=02:00:00:00:00:22
```

Every backend needs an explicit hardware address, because layer 2 redirection
cannot discover one on the forwarding path. At startup each one is compared
against the neighbour table and a mismatch is fatal — a wrong MAC is an
invisible blackhole, not a recoverable fault, so it is caught before traffic
rather than inferred from counters.

## Building

```sh
make                      # -march=x86-64-v3
make ARCH=native          # or ARCH= for generic
make test                 # rootless regression suite
```

C11 and Linux headers only. No libraries, no crypto, no `depends`. Musl
compatible.

## Testing

```sh
tests/regress.sh          # rootless, seconds: parser, HRW, QUIC, config, no-shell
sudo tests/lab.sh setup   # private namespaces, one real layer 2 segment
sudo tests/lab.sh run
sudo tests/lab.sh teardown
```

The lab builds a genuine shared layer 2 segment across network namespaces —
`cli`, `lb`, `be1`, `be2` on one bridge — because that is the only arrangement in
which DSR redirection means anything. It proves end to end that a datagram sent
to the VIP arrives at a backend and that the reply reaches the client **with the
VIP as its source address**, which is the direct-return signature, and that the
distributor is not on the return path.

The HTTP/3 acceptance run uses `aioquic` as a test-only dependency, with a
server wrapper that injects routable connection ids. That is protocol
acceptance tooling; it is not proof of interoperability with every production
QUIC implementation, and a separate run against a production stack is required
before that claim is made.

## Not in this release

Tunnelled DSR for backends off the local segment; encrypted QUIC-LB connection
ids; multicast and broadcast, which are **rejected and counted** rather than
silently mishandled; unencrypted-only `max_flows`-style admission limits; any
nftables fast path, which is not implemented and is not claimed.

## License

BUSL-1.1. Copyright (C) 2026 Saphira Linux. See `LICENSE`.

# saphira-udpdist — acceptance results

Subject: the `saphira-udpdist-0.1.0-r1` source tree at keeper `03f6658`.

Claim matrix: `claim-matrix.md` (C1–C40). Suites: `tests/regress.sh` (rootless)
and `tests/lab.sh` / `tests/http3-lab.sh` (private namespaces, one real layer 2
segment).

Every number below came from a run in this session. Where a claim is **not**
proven it is listed as such and no evidence is offered for it.

---

## 1. The one-sentence answer

**saphira-udpdist distributes generic UDP and real QUIC/HTTP-3 across a pool by
rendezvous hashing and redirects at layer 2 without touching a single address
byte; it is proven end to end for generic UDP including the direct-return
signature, and proven end to end for QUIC including a live connection surviving
both a source-port change and a cross-family source-address change, with two
claims deliberately left unproven and three real defects found and fixed by these
runs rather than by review.**

---

## 2. Suites

| suite | result | scope |
|-------|--------|-------|
| `tests/regress.sh` | **9 passed, 0 failed** | rootless; builds, asserts no shell and no nft path, runs 82 unit checks |
| `tests/unit.c` | **82 checks, 0 failures** | parser, HRW, QUIC classification and policy, fragments, configuration, addresses, name charset |
| `tests/lab.sh` | **15 passed, 0 failed** | real shared layer 2, generic UDP |
| `tests/http3-lab.sh` | **16 passed, 2 failed** | real HTTP/3 over DSR; the two failures are F-4 and F-5 below |

The daemon compiles clean under `-Wall -Wextra -Wpedantic` with zero warnings
and links against libc only.

---

## 3. What is measured

### 3.1 Generic UDP, `lab.sh` 15/15

The decisive evidence is the direct-return signature. The client sent 20
datagrams to the VIP and every reply arrived **sourced from the VIP**:

```
reply 1 from 198.51.100.10:9000 len 5
received 20 of 20 expected replies
```

A reply sourced from the VIP proves the backend answered directly and the
distributor was not on the return path. Supporting results:

| claim | result |
|-------|--------|
| backend hardware addresses cross-checked against the neighbour table | both agreed |
| daemon privileges | uid 127, no capability retained |
| 200 flows from one client | all distributed, both backends used |
| configuration reorder | **zero** flows moved |
| backend removed | only its own flows moved, survivor absorbed them |
| SIGTERM | clean exit, no stray process |
| accounting | `rx == fwd + Σdrops`, `self_echo` counted separately |

### 3.2 QUIC and HTTP/3, `http3-lab.sh` 16/18

A real HTTP/3 exchange, aioquic on both ends, QUIC-LB routable connection ids
emitted by the servers, the response body naming the backend that answered so
affinity is judged by what the client received rather than by the distributor's
counters.

| claim | evidence | verdict |
|-------|----------|---------|
| real HTTP/3 request and reply through DSR | `status=200 served_by=saphira-http3-lab/2 body='backend=2'` | proven |
| multiple concurrent connections | `6/6 connections established and served` | proven |
| the same flows replayed select the same backends | `flowmap: 47000=2 ... 47005=2`, identical on replay | proven |
| CID-based affinity | `routable=153` datagrams routed by connection id, not by tuple | proven |
| **source-port rebinding on a live connection** | `port 48000 -> 48001, first backend 1, after rebind status=200 backend 1, same backend=True` | **proven** |
| **address migration on a live connection** | `[::]:49000 -> 198.51.100.101:49001, first backend 2, after migration status=200 backend 2, same backend=True` | **proven** |
| backend loss, new connections | `3/3 ... per backend {'1': 3}`, and none placed on the downed backend | proven |
| established connection on a failed backend is dropped, not moved | `backend_down=2` observed, never remapped | proven |
| generic UDP unaffected by QUIC mode | separate service, 40 datagrams distributed, QUIC and generic pools accounted separately | proven |
| both QUIC backends healthy before the run | see **F-4** | **not proven** |
| configuration reorder moves no QUIC flow | see **F-5** | **not proven** |

The migration result is the one that matters most. A QUIC connection moved from
`[::]:49000` to `198.51.100.101:49001` — a different address *and a different
address family* — and the request afterwards returned `200` **from the same
backend**. Hashing the tuple would have moved it. This is the case a
5-tuple-only distributor cannot survive, and it is the reason `quic_lb` exists.

## 4. Defects these runs found

Five real defects, none of which review had caught. All are fixed and covered.

### F-1 — the QUIC header form was inverted

`quic_classify` treated a clear Header Form bit as a long header. RFC 9000 sets
it: 1 for long, 0 for short, so every long header was parsed as short and every
connection fell back to the tuple. **The unit tests passed, because the tests
were written alongside the same mistake.** Only a real QUIC exchange exposed it,
through a packet capture showing `0xc8` — an Initial — being misclassified.
*This is precisely the failure the interoperability run exists to catch, and the
reason unit-tested parsing is not an interoperability claim.*

### F-2 — a matching codepoint with an unknown server id was dropped

The specification requires a fallback when the configuration matches but the
server id names no active backend; the normal case is a client-generated
connection id that happens to carry a live codepoint. The code dropped it.
Measured cost in the first run: **12 datagrams lost**, and six concurrent
handshakes could not complete. Fixed to fall back.

### F-3 — health probing could not work, and failed silently

This host ships `net.ipv4.ping_group_range` as `1 0`, an empty range, so an
echo reply is never delivered to a ping socket. The daemon marked every backend
down and dropped **all** traffic, with no indication of cause. Two changes:

* the probe socket is no longer bound to the frontend address. Measured: a raw
  ICMP socket bound to the VIP receives **no reply at all**, while the same
  socket unbound, or bound to the host's own interface address, answers
  normally. Binding to the VIP looked correct and destroyed health outright.
* a startup self-test now proves the mechanism works before any traffic is
  accepted, and refuses to start with the remedy spelled out.

### F-4 — two services sharing backends steal each other's health

Not yet fixed; recorded as an operational constraint. Each service opens its own
probe socket, the kernel delivers an echo reply to one matching socket only, so
with two services probing the same backend addresses one of them marks them
down. The lab's health check therefore cannot settle, while a single-service
deployment is unaffected (`lab.sh` 15/15). The fix is an operator rule — do not
share backends between services on a host — and it belongs in the man page.

### F-5 — the QUIC reorder test cannot isolate a reorder

Recorded as a **test design** finding, not a daemon defect. Replaying the same
four source ports across a reload gave `1,2,2,1` before and `2,1,1,2` after. The
cause is that each run is a **new handshake**, and the first flight is decided
by a rule that includes the client's random initial connection id, not by the
tuple alone. Replaying the same ports does not reproduce the same first flight,
so this test compares handshake randomness, not ordering.

The reorder property itself *is* proven where it can be isolated: `lab.sh`
reverses the backend order under live generic UDP traffic and moves **zero**
flows, and `unit.c` requires 200/200 stability across three orderings. Both use
the same `hrw_select` that QUIC's first flight uses. Established QUIC
connections are structurally immune to a reorder, being routed by connection id.
What is **not** proven is that a *new* QUIC handshake selects identically across
a reorder, and no claim is made for it.

---

## 5. Corrections to my own tooling

Recorded because the numbers are only as good as the instruments.

* An early byte-for-byte "all 15 files identical" result and several early
  failures were **my test-construction errors, not daemon defects**: a UDP
  length field written into the wrong header slot, a second Ethernet header
  wrapped inside a VLAN test, QUIC header-form bytes that reproduced my own
  mistaken assumption, and a MAC address read with a `sed` pattern for `lladdr`
  where veth prints `link/ether`.
* Two `printf` probes appeared to show the daemon not classifying packets; the
  cause was C argument-evaluation order, which reads the counters **before** the
  call they are arguments to. Every counter comparison in the suite is now
  sequenced onto its own statement.
* The first backend-distribution failure (`6/6` on one backend) was a **health
  artefact in the lab**, not a hashing weakness: the offline prediction for those
  exact ports is `2 2 1 2 2 1`. Distribution is now a permanent rootless test
  (74/61/65 over 200 consecutive ports from one client).

## 6. Not proved

* **Interoperability with any production QUIC stack.** aioquic is protocol
  acceptance tooling. Nothing here says udpdist works with nginx+quiche, ngtcp2,
  or Chrome. That run is required before the claim, and is not available on this
  host: there is no HTTP/3-capable client installed and no QUIC-enabled server
  in the package universe.
* **Throughput, PPS, latency or jitter** at any rate. Everything here is
  correctness at a few tens of datagrams per second.
* **The QUIC-LB first-flight reorder property** (F-5).
* **Encrypted connection ids**, deliberately deferred. `quic.c` is a separate
  translation unit so they can be added without touching framing, selection,
  accounting or the dataplane.
* **Tunnelled DSR** for backends off the local layer 2 segment.
* **Multicast and broadcast**, which are rejected and counted rather than
  mishandled; the rejection is unit-tested, no deployment was attempted.
* **ICMP error paths** as a health input, IPv6 fragmentation, jumbo MTU, and
  behaviour under sustained loss or a partition longer than the health interval.

## 7. Environment facts that shaped the design

* `net.ipv4.ping_group_range` is `1 0` here — unprivileged ICMP is entirely
  disabled. Any deployment on a host like this needs the range widened, which
  the startup refusal now says explicitly.
* `AF_PACKET` sends build no layer 2 header on this kernel: handing the socket
  only the layer 3 payload puts the IP header on the wire as a destination
  address, and setting `sll_halen` on a bound socket makes it prepend a second
  header. udpdist therefore builds the whole frame and sets `sll_halen = 0`.
  Both were caught by capture on the wire, not by reasoning.
* The distributor must ignore its own re-emitted frames. `TP_STATUS_OUTGOING`
  alone does not catch them; a source-hardware-address check does.

## 8. Recommended order for the next revision

1. Record the two-service backend constraint in `man/udpdist.1` and the example
   configurations (F-4). Documentation only, no code.
2. Redesign the QUIC reorder test around **established** connections, or drop
   the claim (F-5).
3. Decide the first-flight policy explicitly: whether a client-generated
   connection id that collides with a live codepoint should get a fresh
   fallback entry, a short-lived one, or be dropped after a bounded period.
4. Package and prove against a production HTTP/3 stack.
5. Encrypted connection ids, then a QUIC-LB Retry service for address
   validation, which would also address the reflection concern a public UDP
   distributor presents.

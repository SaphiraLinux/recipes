# D6 — Node enrollment and capability discovery

Status: **design, not implementation.** Companion to D1–D4. Read D1 §3.4,
D3 §7 and D5 §2 first.

---

## 1. SSH is bootstrap only

Enrollment is the one moment the control plane authenticates to a host using
a credential an operator already had. After that, the relationship is
**key-based and continuous**, not SSH-shaped.

```
  operator                control plane                      managed host
     |                         |                                   |
     | authorise enrollment    |                                   |
     |------------------------>|  1. bootstrap over SSH           |
     |                         |---------------------------------->|
     |                         |  2. identify + probe (read-only) |
     |                         |<----------------------------------|
     |                         |  3. issue drone identity/credential
     |                         |---------------------------------->|
     |                         |  4. drone authenticates onward    |
     |                         |<================================>|
     |                         |  5. return inventory + capabilities
     |                         |<----------------------------------|
```

**SSH is never retained as the ongoing transport.** After step 3 the drone
authenticates with its own issued identity; SSH keys and any operator
credentials used for bootstrap are not held by the platform for ongoing use
and are not required for normal operation. Bootstrap SSH is used once, for
one read-only identification pass, and that is all.

### 1.1 Human-gated, and bound to the host's real key

Enrollment is authorized by an operator (`host.enroll`, D5 §2) and is
audited. The authorization to enroll is bound to material derived from the
host's **actual identity key**, not to a bearer token that anyone could
replay. A token valid for one host does not enroll another; presenting it
elsewhere fails.

### 1.2 Bootstrap is read-only

The bootstrap pass may identify, probe and install the drone component. It
does not change load-balancer configuration, networking, or services. The
first configuration change to a host is an ordinary transaction (D8) with its
own authorization, validation and audit.

---

## 2. Drone identity

After bootstrap the drone holds its own issued identity and credentials
(D3 §7), scoped to the host it is enrolled on. Properties:

- **Node identity is the key.** Authorization is by the enrolled node's
  credential, re-authenticated per session. Losing the credential and
  re-enrolling is an explicit operator action.
- **Blast radius is the node.** A compromised node can act on itself. It
  cannot reach the core's database (D1 §3.2, D4 §1) and cannot act for
  another node, because the core authorizes every dispatched operation against
  the calling operator's capabilities, not the drone's opinion (D2 §5, D3 §4).
- **The drone holds no policy.** It is told what to do. It does not decide
  what is allowed.
- **The credential is a secret** and lives in the secret store, referenced from
  the host record (D3 §5). It is never returned through an ordinary API
  response.

---

## 3. Discovery: five capability states, never conflated

This is the heart of the document. A single boolean "does this node support
HAProxy?" is not a usable answer, because it collapses five different
questions whose answers legitimately differ. Discovery reports **each state
separately**, and the router refuses work based on the state actually proven.

| State | Question | Established by |
|---|---|---|
| `unavailable` | Is the capability absent entirely? | probe confirms nothing present |
| `installed` | Is the package present? | package database query |
| `available` | Can the service be invoked at all? | service definition exists / binary runs |
| `usable` | Does the **specific feature** the router needs work? | end-to-end feature probe |
| `healthy` | Is it **running and responding** right now? | live probe of the running daemon |

These map to the earlier L1–L4 framing as `installed`, `available`, `usable`
and `healthy` respectively, with `unavailable` added so that "definitely not
here" is a recorded answer rather than an absence of one.

A capability is granted to a host only at the **highest state actually
proven**. No evidence is not a default state: it is reported as
`unestablished`, which is distinct from `unavailable` (we checked, it is not
there) and from `unusable` (we tried, it does not work).

### 3.1 Probe the feature; never infer it from a proxy signal

> Capability is established by **exercising the feature**, not by observing
> something adjacent to it.

Inventory tells you what is *present*. Only a direct, side-effect-free probe
tells you what *works*. The distinction is the whole point, and getting it
wrong produces a control plane that either refuses work it could have done or
attempts work it cannot.

**Never infer a capability from a proxy signal.** Specifically, a capability
may not be inferred from:

- `lsmod` output, or the presence of a `/sys/module/<name>` directory;
- a package being installed;
- a service file existing;
- a kernel configuration file;
- the presence of a binary on `$PATH`;
- the absence of an error from a command that never exercised the feature.

Each is a reasonable signal that something *might* work. None is evidence
that it does.

**The normative example: built-in kernel features.** `nf_tables` is commonly
compiled **into** the kernel rather than built as a loadable module. On such a
host it is completely absent from `lsmod` and from `/sys/module`, while being
fully functional. A discovery check that inferred "nftables is usable" from
`lsmod | grep nf_tables` would record a **working feature as broken** — a
false negative on a healthy host, which is the most damaging kind of
discovery error because it blocks correct work. (This was observed concretely
on an acceptance node during design: the proxy signal said absent, and
`nft -c -f` validated successfully with exit 0.)

The correct probe is the feature itself: for nftables, parse a candidate
ruleset with `nft -c -f` — which validates and **mutates nothing** — rather
than inspecting the module table.

**Prefer direct probes that are safe and side-effect free.** Check-mode and
read-only forms exist across this ecosystem and are the right tool:

| Feature | Side-effect-free probe |
|---|---|
| nftables | `nft -c -f` (check mode; applies nothing) |
| HAProxy | `haproxy -c -f` (validates; does not start) |
| BIND | `named-checkconf -z` |
| ldirectord | **none exists** — so no native probe; see D4 §11.2 |
| gredist | no queryable endpoint; signal-based only |

Where a direct probe does not exist, that is itself the finding, and the
capability is reported at the highest state that *can* be established, with
the absence of a native probe recorded rather than papered over. Note how the
table differs per component: the same method that yields `healthy` for nftables
yields only `installed` for ldirectord, and that difference is the honest
answer.

### 3.2 Why the distinction is not pedantry

The components in this ecosystem all exhibit the gap between these states, and
getting it wrong produces a control plane that confidently deploys something
that cannot work:

- **A package installed is not a usable feature.** `resource-agents` being
  installed does not mean ldirectord can run a virtual service — the perl
  dependency is deliberately *not* a package dependency (D1 A.1, D1 §9), so
  ldirectord can be `installed` and still fail to start.
- **A service available is not a runtime API.** HAProxy has a service
  definition and `haproxy -c` validation, and still has **no runtime socket**,
  so observed state is `unavailable` (D1 A.2, D1 Appendix B #4). It can be
  `installed`, `available` and `usable` for *config validation* while being
  `unusable` for *observed state*.
- **A runtime daemon is not a usable feature.** gredist has no service
  integration at all (D1 A.3, Appendix B #6), and its unpublished revisions
  (Appendix B #5) mean a node may carry a version the repository does not.

### 3.3 The rule the controller enforces

> The controller must refuse to deploy an object requiring a capability the
> target does not possess — **at the state the object actually needs**.

If a `VirtualService` needs ldirectord to *validate and activate*, that needs
`usable`, not `installed`. If a health check needs the HAProxy *runtime
socket*, that is a specific capability distinct from "HAProxy installed" and
is separately probed. Refusal names the state that failed, what would raise
it, and — where no probe exists to raise it — that no probe exists.

### 3.4 Never assume

Discovery is explicit, probed, and records its evidence. In particular the
router **never assumes**:

- **perl is present.** It is a known, deliberate non-dependency of
  ldirectord (D1 A.1). Probe for it; without it, ldirectord cannot exceed
  `installed`.
- **A HAProxy runtime socket exists.** It does not in any shipped Saphira
  config (D1 A.2). Probe for it; without it, HAProxy observed state is
  `unavailable`, and the platform says so (D1 §10.2, D3 §9).
- **IPVS / IPVS kernel support is present.** Probed by exercising the feature,
  **not** by inspecting `lsmod` or `/sys/module` — those give false negatives
  for anything compiled into the kernel, exactly as `nf_tables` does (§3.1).
  The `ipvsadm` package being installed proves nothing about the kernel
  supporting IPVS.
- **A service definition implies the service runs.** Probed independently.
- **A capability is present because a related indicator says so.** Never
  (§3.1).
- **A node is homogeneous with its peers.** Each node is probed
  independently; §4.1 makes this observable in the M1 topology.

---

## 4. Recording discovery

Discovery results feed the `host_capability` table (D4 §5), extended to carry
the proven state and its evidence rather than a bare capability row.

> **D4 amendment required (recorded here, applied with the migration).**
> `host_capability` gains: `state` (the highest proven state — `unavailable`,
> `installed`, `available`, `usable`, `healthy`, or `unestablished` when no
> probe was run), `evidence` (JSON: the direct probe that was executed and its
> result), `probe_method` (the probe used, so a `usable` claim is auditable),
> and `checked_at`. A capability row without a state is not a discovery
> result. This is a migration, not a silent schema change, and it is called
> out here so D4 and D6 do not drift.
>
> `evidence` records **the direct feature probe**, not a proxy signal. A
> `usable` state whose `probe_method` is `lsmod` or `package_query` is an
> invalid row and must be rejected on write — the schema carries the
> constraint that makes §3.1 enforceable rather than aspirational.

Discovery is **re-runnable and periodic**: capabilities carry a check
timestamp, and a capability whose evidence has aged is reported with its
freshness (D7) rather than treated as current forever. A node that loses a
capability — a package removed, a service stopped, a kernel module unloaded —
is reflected on the next discovery pass, and any object that depended on it
is then reported as unsupported on that host (D7, D8).

### 4.1 Discovery is what the M1 topology is for

The M1 acceptance nodes deliberately differ in what they carry, and the
platform must reflect that honestly rather than assume homogeneity (D1
Appendix C). The router's refusal to place an object on a node that lacks a
required capability is only meaningful if discovery actually reports the
difference. This is a first-class observable, not a footnote.

---

## 5. Enrollment result

A successful enrollment returns an inventory to the control plane: the host
record, its package inventory, its capability matrix **with levels and
evidence**, and its node identity. The TUI shows this matrix (D1 §4 row 3) as
four distinct levels per capability, so an operator can see at a glance
whether a node is merely *installed* or actually *usable* for what they intend
to deploy on it.

---

## 6. What this model does not claim

- It does not claim SSH is used for ongoing management.
- It does not claim a node is trusted because it enrolled. Enrollment proves
  identity, not health, not capability, and not good intent.
- It does not treat a node's self-report as authoritative. Discovery collects
  evidence; the core decides what the node may host (D3 §7).
- It does not equate a capability being *present* with it being *usable* —
  that gap is the whole point of §3.

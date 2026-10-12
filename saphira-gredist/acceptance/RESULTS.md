# saphira-gredist — multi-host acceptance results

Subject: the **published** `saphira-gredist-0.1.0-r5`, installed from the live
`hatched` repository on nodea / nodeb / nodec, plus a `r6` rebuild used only to
test the release gate.

Claim matrix: `claim-matrix.md` (C1–C23 + INV-1). Harness: `topology/`, `tests/`.
Runtime evidence for every number below is under
`/build/tmp/opencode/gredist-acceptance/20260928T122200Z/`.

> Evidence-root note: the plan named `/build/gredist-acceptance/<ts>/`, but this
> session's sandbox discards writes outside `/build/tmp/opencode/`, so evidence
> lives at `/build/tmp/opencode/gredist-acceptance/<ts>/`. Same content, same
> machine, reproduced by re-running `acceptance/run.sh` (see README).

---

## 1. The one-sentence answer

**saphira-gredist provides exactly one distributed property: a GRE packet that
arrives at a frontend address on one host is deterministically assigned by
rendezvous hashing to a backend address on another host, and the GRE header and
inner payload are forwarded byte-for-byte with the outer IP envelope rebuilt;
that is all, and it holds under normal operation, under `SIGHUP` reload of the
backend list, and across peer loss and recovery — but it breaks silently, with
no counter and no log line, the moment an operator reloads a changed `frontend=`
or points one service's backend at another service's frontend.**

---

## 2. Three evidence tracks, kept separate

| Track | Question | Result |
|-------|----------|--------|
| 1. release/provenance | how did r4/r5 reach production? | **release gate bypassed** (F-1) |
| 2. packaging/installability | does the published package install? | **yes** (F-2) |
| 3. runtime behaviour | what does the binary do across three hosts? | **measured**, see §5 |

### F-1 — the PASS gate was bypassed, and the gate is structurally unable to pass

All eight `saphira-gredist` rows in `/var/lib/saphira-build/queue.db` are `FAIL`
with `published_at` NULL. `saphira-build publish` selects only
`state='PASS' AND published_at IS NULL`, so the queue-aware publisher has never
been willing to publish this package. Yet r4 and r5 are in the live repository
and served from `packages.saphira.vm2.uk/hatched`. `sign-apk-repo` has no queue
awareness and publishes every `*-ready` transaction it finds, so a direct
invocation is the only path consistent with the evidence.

**This is not a one-off mistake, and the gate is still broken.** r6, built from
today's tree with today's packager, reproduced the identical INSTALL failure:

```
ERROR: unable to select packages:
  saphira-gredist-0.1.0-r5:
    breaks: saphira-gredist-doc-0.1.0-r6[saphira-gredist=0.1.0-r6]
```

The defect is in the daemon's INSTALL stage, not in the package. Proof, same
index, same transaction:

| test | command | result |
|------|---------|--------|
| A (what the daemon does) | `apk add saphira-gredist-doc-0.1.0-r6.apk` | **fails**, exact error above |
| B | `apk add saphira-gredist-0.1.0-r6.apk saphira-gredist-doc-0.1.0-r6.apk` | **succeeds**, 4 packages, payload runs |

The stage adds only the *last* subpackage file and expects the base to come from
the repository index. A subpackage that pins its base by exact version can never
be satisfied that way once any other base revision exists in the index. So
**saphira-gredist cannot reach PASS**, which is precisely why it is in production
without having passed. Fixing this belongs to the packager/build-daemon work and
is deliberately not done here.

### F-2 — the published package itself is sound

r5 base and `saphira-gredist-doc` install cleanly on all three nodes. Base
metadata is `depends: iputils` only, no `breaks`, no `provides`. The historical
`apk add rc=2` was this same harness artefact, not a recipe defect.

---

## 3. r5 vs r6

| | r5 | r6 |
|---|---|---|
| in live repo | yes, published | no, could not pass the gate |
| built from | unmerged `hotfix/var-packaging-bug-var-run-isnot-run` | `feature/bunny` @ `f610260` |
| build queue | 6 rows, all FAIL | 1 row, FAIL (same cause) |
| `/usr/bin/gredist` | `d0da71b9…` | `d0da71b9…` |
| `/usr/bin/gre-sink` | `d38d904f…` | `d38d904f…` |
| `/usr/bin/gre-send` | `57798099…` | `57798099…` |

**r6 is byte-for-byte identical to r5.** The only C difference is the dead
`DEFAULT_STATS_PATH` define, which the compiler discarded entirely. r6 therefore
reproduces the published artefact exactly, and the entire r5 runtime evidence
below transfers to r6 verbatim rather than needing a second run. It also proves
the build is deterministic.

---

## 4. Topology

Additive only. A fresh OVS bridge `gretest` per host plus a **loop-free VXLAN
chain** `nodea —[VNI 47701]— nodeb —[VNI 47702]— nodec` over the working
management IPv4 network, and one `grecli` netns per host so GRE sources originate
on three different hosts.

Two topology facts worth recording, both discovered by measurement:

- A **full mesh** of VXLAN ports on one flat bridge is an L2 loop. It passed
  ~12M frames per port within minutes and only nodea could reach nodeb. Per-link
  VNIs do not fix it — they separate tunnel keys, not the bridged loop.
- Frontend and backend address spaces **must be disjoint**. An early revision
  pointed `svc-a`'s backends at `10.77.0.12`, which was `svc-b`'s frontend. Since
  gredist forwards GRE payload byte-for-byte and decrements nothing, the two
  daemons became a forwarding loop: **871,962 packets received for 30 sent**,
  every vxlan port carrying ~4.3M frames. See F-6.

Six services, one frontend on each host, v4 and v6 and both cross-family
directions. Teardown was verified: `ovs show`, `ovs list-br`, `ip -br addr`, both
route tables, `nft list ruleset` and `ip netns list` are **identical** to the
recorded post-upgrade state on all three nodes. Only the package under test
remains installed.

---

## 5. Runtime results

Environment: identical binary hash on all three hosts; all gredist processes run
as **root** for their whole lifetime; all six backends healthy.

### 5.1 What works — confirmed

| Claim | Result |
|-------|--------|
| C1/C15 cross-host forwarding | **confirmed**, 90 sent, 90 delivered, exact conservation |
| C5 v4→v6 cross-family | **confirmed**, 30 sent, 30 delivered to v6 backends, payload preserved |
| C12 HRW determinism | **confirmed**, 57/57 flows stable across identical runs |
| C14 health transitions | **confirmed**, DOWN/healthy logged within ~4s of ICMP loss |
| C13 health-driven removal | **confirmed**, see 5.2 |
| C2 multi-service | **confirmed**, two independent services per host, own pools, own stats |
| C8 signals | **confirmed**, SIGHUP reload, SIGUSR1 dump, SIGTERM clean exit |
| C17/C18 build + licence | **confirmed**, C11 musl, `-march=x86-64-v3` |
| C22 no healthy backend → drop | **confirmed** |

Delivery detail for the 90-packet run — `rx == forwarded`, `gap == 0` for every
service, and `Σ sink == forwarded` exactly:

```
svc-a nodea  rx= 30 fwd= 30  backends 10+20 = 30     v4 -> v4, cross-host
svc-b nodeb  rx= 30 fwd= 30  backends 13+17 = 30     v4 -> v4, cross-host
svc-c nodec  rx= 30 fwd= 30  backends 13+17 = 30     v4 -> v4, cross-host
svc-y6 nodeb rx= 30 fwd= 30  backends 14+16 = 30     v4 -> v6, cross-family
```

### 5.2 The HRW claim, split as required

**Health-driven removal — C13 holds.** Backend `10.77.1.12` made unreachable;
gredist marked it `DOWN`; the same 60 flows were re-sent:

```
32 stable, 25 moved
  nodeb -> nodea   16      <- removed backend
  nodeb -> nodec   9      <- removed backend
```

Every single move originated at the backend that went away. **Zero remapping
among the backends that stayed healthy.** Exactly what rendezvous hashing
promises.

**Config-list edit — C13 is contradicted.** No backend was removed and all three
stayed healthy; the config lines were merely reordered `[11,12,13] → [13,12,11]`
and reloaded with `SIGHUP`:

```
24 stable, 32 moved
  nodea -> nodeb   6      nodeb -> nodea   3
  nodea -> nodec   7      nodeb -> nodec  7
  nodec -> nodea   8      nodec -> nodeb  1
```

**57% of flows moved for a no-semantic-change edit.** Cause: `gre.c:182` mixes
the backend's **array index** into the score, so shifting a line changes every
later backend's score and the whole mapping is recomputed. Pure HRW would leave
all of them alone.

### 5.3 Failure and recovery

| scenario | observed |
|----------|----------|
| backend unreachable | marked DOWN in ~4s; its flows move; survivors stable (5.2) |
| backend restored | marked `recovered (healthy)` in the log; deterministic rejoin |
| all backends down | every packet dropped, `no_backend` accounting correct |
| `SIGHUP` with a broken config | old config retained, failure logged — sound |
| `SIGHUP` after a `frontend=` change | **silent blackhole**, see F-3 |
| crash / kill | no state to lose; the `nft` table is left behind, see F-4 |
| loop amplification | unbounded, see F-6 |

### 5.4 INV-1 — observed disposition

`rx == forwarded + Σdrops` held (`gap = 0`) in every steady-state test. Two
places where a packet has **no disposition at all**:

- **`F-3`**: a packet delivered to a reloaded `frontend=` produces no counter and
  no log line.
- **`forwarded` is not a delivery receipt.** In one 60-packet run, 59 reached the
  frontend and 57 reached a backend, while gredist reported `fwd=60` with
  `queue=0` and no drop of any kind. `forwarded` means "accepted by the kernel";
  the `queue` counter only counts `sendto()` failures. Loss after the send is
  invisible. This is inherent to fire-and-forget GRE and not a defect, but the
  documentation's "counted as drops" invites the opposite reading, so INV-1 can
  only be met approximately for the delivery leg.

---

## 6. Findings

### Implementation defects

**F-3 — `SIGHUP` frontend change is a silent blackhole. Highest severity.**
`gredist.c:354-373` replaces the service struct on reload but never re-opens or
re-binds the receive socket. Measured:

```
control, before reload : rx 240 -> 241, fwd 240 -> 241, backend pkts 0 -> 1   OK
SIGHUP frontend=10.77.0.21  -> "reloaded 3 backends"   (no warning)
packet to 10.77.0.21   : arrived at the host and at the new address (sink saw it)
                          rx stayed 241, fwd stayed 241, no backend received it
```

No counter moved. No log line. The service is permanently deaf on its new
address with no symptom. Smallest fix: reopen and re-bind the receive socket
when the frontend family or address changes. The privilege probe shows `bind()`
on an existing raw socket succeeds for an unprivileged user, so this fix does
not require keeping root.

**F-4 — the nft "fast path" is unimplemented, and leaves unowned state.**
`try_setup_nft` creates `table inet saphira_gredist_<name>` and then runs
`nft 'add chain … type nat hook prerouting …'` with its output discarded. The
chain never appears. Every table measured on all three hosts is completely
empty:

```
table inet saphira_gredist_svc-a {
}
```

No DNAT rule, no chain, no acceleration — C9 is unimplemented, and the code says
so in its own log line: `(placeholder, userspace owns HRW)`. The tables are
never removed, not on `SIGTERM` and not on crash; nodea carried four stale
tables from earlier runs. They are also created for cross-family pools that skip
the nft path entirely on other hosts. Smallest fix: delete the nft path — it
does nothing — which also removes the daemon's only CAP_NET_ADMIN requirement.

**F-5 — the HRW score depends on the backend's array index.** `gre.c:182`.
See 5.2. Directly contradicts C13 in README and man. Smallest fix: drop the
`(uint64_t)i*0xbf58476d1ce4e5b9ULL` term so the score depends only on the
backend identity and the flow.

**F-6 — forwarding is unbounded and loop-amplifying.** No TTL decrement, no hop
limit, no loop detection. A backend address that is reachable as another
instance's frontend produces an unbounded storm (measured 871,962 rx for 30
sent). Smallest fix: document it as an operator constraint, and/or refuse a
config whose backend set overlaps a local service's frontend — which the daemon
cannot know, so at minimum it belongs in the man page.

**F-7 — the health probe blocks the dataplane.** `probe_backend` forks `ping` and
waits synchronously, inside the event loop. Measured event-loop latency via
SIGUSR1 dump response:

| backends down | dump latency |
|---------------|--------------|
| 0 | 3–5 ms |
| 1 | ~1030 ms (alternating with 3–5 ms) |
| 3 | **~5510 ms** |

With 3 dead backends the loop is blocked for 5.5 s on a 2 s tick — blocked
longer than the interval, i.e. permanently. 20 packets sent during that window
produced `rx=0`. A pool with several unreachable backends takes the distributor
offline. Smallest fix: probe each backend in a child that is reaped
non-blockingly, so the loop never waits on `ping`.

**F-8 — the `IP_HDRINCL` contradiction loses every packet.** `gredist.c:190`
sets `IP_HDRINCL` on the lazily-opened send socket; the comment three lines
below says it must not be set. Forced with an `LD_PRELOAD` shim failing only the
send-socket pre-open (call #2), so `forward_packet`'s lazy path is the first
success:

```
rx=5  forwarded=0  queue=5      nodeb sink received 0 packets
```

Every packet is rejected by the kernel and misreported through the `queue`
counter, which is the same counter used for genuine queue pressure and for an
unreachable backend. The latent risk is worse than loss: with `HDRINCL` set the
kernel builds an outer header out of whatever bytes are at the front of the
buffer, so a GRE header whose first byte parses as a plausible IHL would be
transmitted as genuine corruption to the backend rather than dropped. Smallest
fix: delete the `setsockopt` line.

**F-9 — shell injection via the `-c` config basename.** `gredist.c:268-274`
derives the service name from the config path basename with **no** validation,
while the positional service name is charset-checked at `gredist.c:262-263`.
`try_setup_nft` interpolates that name into `system("nft list table inet %s …")`.
Proven on a disposable node with a harmless marker:

```
config file : x$(touch INJECTED_POC).conf
gredist -c  : "starting service x$(touch INJECTED_POC) …"
              -> INJECTED_POC created, owned by root
benign basename control : marker not created
```

It fires before any socket is opened, so it needs no working configuration.
Smallest fix: remove the shell entirely — `execv`-style argv execution for
`nft`, plus explicit validation of the derived name. This must be fixed
independently of privilege dropping: the point is that `/bin/sh` must never see
the string, not that it would see it as a lesser user.

### Working with an undocumented limitation

- **`forwarded` is not a delivery receipt** (§5.4). Inherent to GRE; document it.
- **RCVBUF is requested, not guaranteed.** `setsockopt` return values are
  discarded. Measured on these hosts: asked 4 MiB, effective 8 MiB (Linux
  doubles), granted only because `net.core.rmem_max` is exactly 4 MiB. Lower it
  anywhere and the request is silently clamped.
- **Stats are not machine-readable and have no durability.** `/run/saphira/gredist/`
  is documented in the man page, `DEFAULT_STATS_PATH` is dead code, no directory
  is ever created, and a restart zeroes every counter. Health and counters are
  process memory only.
- **Backends are optimistically healthy.** `config.c:106` sets `healthy=1` at
  load, so a known-dead backend takes traffic for ~4 s after every start and
  after every `SIGHUP`.
- **IPv6 link-local needs a scope.** `inet_pton` is the only parser, so `fe80::1`
  and any `%iface` form cannot be expressed.
- **No source authentication of any kind.** Any host that can reach the frontend
  gets its protocol-47 traffic forwarded into the pool. No allowlist, no ACL, no
  rate limit; the key is explicitly not a secret.

### Documentation defects

- **C9 claims a kernel `nft` fast path that does not exist** (F-4).
- **C13's "surviving mappings remain stable" is false for config edits** (F-5).
- `/run/saphira/gredist/` documented, never created.
- `MAX_BACKENDS=64` and the `MAX_FRONTENDS`/`MAX_BACKENDS` bounds are undocumented.
- No init service, systemd unit, sysusers fragment or account is shipped, so
  "control service" has no service definition and there is nothing to run it as.

### Missing tests

- The shipped `lab.sh` **cannot fail**: `do_run` ends in `echo` + `cleanup`, and
  in this run it printed `FAIL queue dropped all` and still exited 0, which
  `run-tests.sh` reports as `LAB PASS`.
- Its only measurement function, `count_hits`, is `awk`-based, and `/usr/bin/awk`
  on these hosts is gawk with no `libmpfr` (mawk absent). The `2>/dev/null || echo 0`
  fallback turns a hard tool failure into a silent "0 hits". Measured: 3 packets
  demonstrably delivered, reported as 0.
- The installed copy of `lab.sh` / `run-tests.sh` **cannot run at all** — they
  resolve `SRC_DIR` to `/usr/share/src`, which the package does not ship.
- `run-tests.sh` "unit: config parse" never parses a config: `--help` returns
  before `load_config`. Both `assert "[ $? -eq 0 ]"` lines are unreachable under
  `set -e`. It writes into the source tree and uses host `/tmp`, which
  `RECIPE_RULES.md` forbids.
- Never covered by anything: signals, the nft path, cross-family forwarding
  assertions, health *timing*, `MAX_BACKENDS`, oversized (>9000, unreachable at
  MTU 1500 because the shipped `-m 4` actually fragments), and reload of a
  changed `frontend=`.

### Confirmed working

Cross-host forwarding for v4→v4, v6→v6 and both cross-family directions;
per-flow HRW determinism; health-driven minimal-disruption redistribution;
`SIGHUP` reload of the backend list; SIGUSR1 stats; SIGTERM clean exit; config
validation; the GRE parser's fidelity to `gre_demux.c` on version, routing,
truncated claims and `CSUM|KEY|SEQ` length; determinism of the build.

---

## 7. Privilege: what gredist actually needs (measured, not assumed)

Measured on a node with a throwaway account (`gredistprobe`, since removed):

| operation, after `setgroups`/`setgid`/`setuid` | result |
|---|---|
| `sendto()` on the pre-opened raw socket | **OK** |
| `bind()` a raw socket to the frontend | **OK** |
| `fork()` + `exec("ping -c1 -W1")` | **OK** |
| `socket()` a **new** raw socket | **EPERM** |
| `setuid(0)` / `setgid(0)` | **EPERM** (cannot regain) |

So gredist needs `CAP_NET_RAW` **only to create its sockets at startup**, needs
no capability at all to forward or to rebind, and needs `CAP_NET_ADMIN` only for
the nft call — which F-4 shows is a no-op and can simply be deleted. The health
probe survives the drop because `net.ipv4.ping_group_range = 0 2147483647` on
these hosts permits unprivileged ICMP for every gid; that is a host sysctl
dependency, not something the daemon can rely on silently.

**Conclusion from the measurement: the minimal shape is a plain in-daemon drop,
and no privileged parent is needed.** root bootstrap (create sockets) → drop
supplementary groups → `setgid(gredist)` → `setuid(gredist)` → verify no regain
→ run the event loop on the inherited descriptors. It also *fixes F-3*, because
`bind()` post-drop works.

House idiom for the account, from `/usr/share/saphira/accounts.d/openssh` and
`saphira-proxyto`: a `files/accounts.d/saphira-gredist` fragment with
`user gredist <uid> gredist /var/empty /sbin/nologin` and `group gredist <gid>`,
in the preferred **0..199** range, never reused.

One blocker to solve in that work, already measured: r5 ships `/etc/saphira` as
**0750 root:root**, so a `gredist` user cannot traverse it and cannot read its
own config. The path must become group-owned by `gredist`. Note also
`subordinate-ids.sh`: the apk payload has no xattr channel, so the drop must be
in-daemon and must not rely on a file capability.

---

## 8. Not proved

- Throughput, PPS, latency or jitter at any rate. Everything here is
  correctness at a few tens of packets per second.
- Behaviour with a jumbo-MTU interface, so the `>9000` oversized path is still
  unexercised.
- IPv6 outer headers carrying extension headers (Hop-by-Hop and friends): the
  code has no extension-header walk, and its headerless fallback re-parses the
  IPv6 header as GRE and forces `dst_match=1`. Predicted from reading; not
  measured.
- The `HDRINCL` corruption variant of F-8 (only the loss variant was observed).
- Behaviour under real-world loss, reordering or a partition longer than the
  health interval, beyond the blackhole and loop cases measured.
- Any TLS/crypto, persistence or multi-instance coordination property: gredist
  has none, and none was looked for.

---

## 9. Recommended order for the r7 work

1. **F-9** remove the shell. Smallest, most severe, independent of everything else.
2. **F-4** delete the nft placeholder — removes the only `CAP_NET_ADMIN` need and
   all the unowned firewall state.
3. **F-7** make health probing non-blocking. This is the difference between a
   distributor and a service that goes offline when a backend dies.
4. **F-3** rebind on frontend change; F-5 drop the index term; F-8 delete the
   `setsockopt`.
5. Privilege drop with a real `gredist` account, per §7.
6. Documentation: C9 and C13 corrected, `/run/saphira/gredist/` removed,
   `forwarded` defined as "accepted by the kernel", bounds and the loop
   constraint written down.
7. Test harness: make `lab.sh` assert and fail, replace `awk` with something
   that works, and either fix or drop the installed copies.
8. Separately, for the packager/build-daemon: fix the INSTALL stage so it
   installs the whole transaction rather than the last subpackage alone. Until
   then no package with a version-pinned subpackage can ever reach PASS, and
   saphira-gredist is the proof.

---

# Addendum: r7 — the measured defects, fixed and re-proved

`r7` is the first corrective revision. It contains fixes for the findings above
that are independently provable without touching the privilege model. Two
measured defects are deliberately **not** in r7 and are scheduled: non-blocking
health probing (r8) and the `SIGHUP` frontend rebind together with the in-daemon
privilege drop (r9), which are coupled because rebinding requires the receive
sockets to be pre-opened at bootstrap, which is precisely what dropping
privilege forces.

Regression suite: `tests/regress.sh`, **25 pass / 0 fail**, rootless, seconds to
run. Every behavioural claim below was then re-proved on all three hosts.

## r7 build and release

| | |
|---|---|
| commit | `d465ef2` |
| recipe | `pkgrel 6 -> 7`, no metadata other than the revision |
| build | `buildpkg rc=0`, staged `saphira-gredist-0.1.0-r7` |
| install gate | **FAIL again**, third consecutive reproduction of the *same* INSTALL defect |
| `apk add` base+doc | installs cleanly (4 packages) |
| binary | `fc763161229dd154…`, genuinely different from r5/r6's `d0da71b952273992…` |
| published | **no** — the gate cannot pass, so r7 is not in the repository |

The gate failure is byte-for-byte the same class as r1–r5 and r6:

```
saphira-gredist-0.1.0-r5:
  breaks: saphira-gredist-doc-0.1.0-r7[saphira-gredist=0.1.0-r7]
```

## F-9 — shell injection: closed

Re-ran the exact acceptance PoC against the deployed r7 binary:

```
config path : /root/gredist-acceptance/x$(touch INJECTED_POC).conf
gredist -c  : "gredist: invalid service name in config path"
marker      : absent-BLOCKED          (r5: PRESENT, root-owned)
```

`regress.sh` blocks that basename plus `;`, backtick, `|`, `&`, `$`, newline,
`..` and `*`, in both the `-c` and positional forms, and asserts that no
`system()` or `popen()` remains in the daemon. There is now no code path from
any input to a shell.

## F-4 — the nft placeholder: removed, not re-implemented

r7 creates **zero** nft tables on all three hosts, and logs no fast-path claim
(`svc-a: ready`, and nothing else). The claim is removed from README and the man
page rather than left standing on a placeholder. This also deleted the daemon's
only use of `CAP_NET_ADMIN`, which is what makes the r9 privilege drop possible
without a privileged parent.

## F-5 — HRW backend identity: fixed, and the isolation held

The repair is the one-line removal of the array-index term from the score. Two
independent proofs, because one alone would not be convincing:

**Offline, 200 flows under three orderings of the same backend set:**

```
200/200 flows stable across three orderings
```

**On three hosts, the exact test that found the bug** (identical 60 flows,
identical clients, only the config line order changed, `SIGHUP` reload):

| | r5 | r7 |
|---|---|---|
| config reorder `[11,12,13]` → `[13,12,11]` | 24 stable, **32 moved** | **57 stable, 0 moved** |

And the health-driven case did not regress — it must still move the affected
flows:

```
r7 health-driven removal of 10.77.1.12:
  40 stable, 17 moved
    nodeb -> nodea   10      <- the backend that went away
    nodeb -> nodec   7      <- the backend that went away
```

**Zero survivor movement in both cases.** C13 now holds as written, for both
membership change and configuration change.

## F-8 — IP_HDRINCL: fixed, and proved at the sink

| | r5 | r7 |
|---|---|---|
| lazy send path, forced open | `queue=5` (every packet rejected) | `forwarded=5, queue=0` |
| observed at the backend sink | — | **5 of 5 delivered**, keys intact, payload `PAYLOADMARK` intact |

**Correction to the record.** In the r5 acceptance run I reported "nodeb's sink
received 0 packets" as corroboration for the `IP_HDRINCL` loss. That
corroboration was a test artefact: the check ran on nodea and read
`logs/sink-b-bv4.log`, which lives on nodeb, so it read a file it had just
created empty on the wrong host. The r5 *counter* evidence (`queue=5`, i.e. total
loss) was genuine and correctly measured, and the defect was real; only the
sink-side corroboration was wrong. The r7 result above was re-run with the sink
read on the correct host and is sound.

## INV-1 — every accepted packet now has a disposition

| path | before | after |
|------|--------|-------|
| outer destination is not the frontend | bare `continue`, **no counter** | `not_for_us` |
| oversized >9000 | counted twice (`oversized` **and** `malformed`) | counted once, as `oversized` |
| unparseable IPv6 (extensions before GRE) | headerless fallback re-parsed the IPv6 header as GRE and **forced `dst_match=1`** | counted `malformed`, fails closed |
| IPv6 fragment | counted `malformed` | counted `frag` |
| `oversized`, `not_for_us` in the SIGUSR1 dump | absent | present |

`rx == forwarded + Σdrops` held with `gap=0` on every service in the r7 run.

The IPv6 fallback removal is evidence-backed rather than assumed: across the
whole r5 acceptance run it never fired once, on any IPv6 delivery, and
`gre-sink`'s own log of the fallback firing was empty — Linux does deliver the
IPv6 header on an `AF_INET6 SOCK_RAW` receive. It was dead code whose only
effect when it did fire was to accept a packet without checking its destination
and to risk forwarding an IP header as tunnel payload.

## Teardown

After the r7 run, `ovs show`, `ovs list-br`, `ip -br addr`, both route tables,
`nft list ruleset` and `ip netns list` are identical to the recorded baseline on
all three nodes; `ip netns list` is empty. The only residue is the package under
test, `saphira-gredist-0.1.0-r7` plus its doc subpackage.

## Still open after r7

- **F-3** `SIGHUP` frontend change remains a silent blackhole (r9).
- **F-7** the health probe still blocks the event loop: ~1.03 s with one dead
  backend, ~5.5 s with three (r8).
- **F-6** forwarding still has no loop detection.
- The release gate still cannot pass, so **none of r7 has been published**. The
  packager INSTALL fix remains the separate work item, and it is now proven
  necessary three times over rather than once.

---

# Addendum: r8 — health probing no longer stalls forwarding

`r8` replaces the synchronous probe with detached children. It is the only
change: no counter, no config field, no wire behaviour and no health threshold
was touched, so every r7 result stands.

Regression suite: **36 pass / 0 fail** — the 25 r7 tests unchanged plus 11 new
ones locking in the structural properties of the fix. The behavioural proof
needs real unresponsive peers, so it is the three-node run below.

## r8 build and release

| | |
|---|---|
| commit | `277469d` |
| recipe | `pkgrel 7 -> 8`, no other metadata change |
| build | `buildpkg rc=0`, staged `saphira-gredist-0.1.0-r8` |
| install gate | **FAIL**, fourth consecutive reproduction of the same INSTALL defect |
| `apk add` base+doc | installs cleanly |
| binary | `d1a68217a9e39b55…` (r7 was `fc763161229dd154…`) |
| published | **no**, for the same reason as r7 |

The packager INSTALL-stage defect is untouched here and remains a separate
build-system blocker, as instructed.

## The measurement that was the point

Identical method to the r7 run: `SIGUSR1` sets a flag the main loop honours, so
the time from signal to the dump appearing is how long the loop was unavailable.
Dead backends are produced by removing the backend's address, which makes its
ICMP probe a blackhole.

| backends down | r7 (synchronous) | **r8 (detached)** |
|---------------|------------------|-------------------|
| 0 | 3–5 ms | **3–5 ms** |
| 1 | ~1030 ms | **3–5 ms** |
| 3 | **~5510 ms** | **3–5 ms** |

**Forwarding latency no longer scales with the number of dead probes.** It is
flat at 3–5 ms, which is the same as the zero-dead case and is the loop's normal
floor.

The decisive difference is not the latency but the accounting. r7, three dead
backends, twenty packets sent:

```
rx=0
```

The loop never reached `poll`, so the packets were never even read. r8, the same
twenty packets against the same three dead backends:

```
rx=20 forwarded=0 malformed=0 truncated=0 frag=0 vers=0
   no_backend=20 queue=0 oversized=0 not_for_us=0
```

Every packet was received and attributed to `no_backend`, which is the
documented behaviour when no backend is healthy. **`rx == forwarded + Σdrops`
holds with `gap=0` in the total-failure case** — on r7 the invariant could not
even be evaluated, because the packets were invisible.

## Health behaviour is preserved exactly

Cadence 2 s, thresholds 2 consecutive failures to down and 2 successes to up,
and the transition log lines are byte-identical to r7. Convergence re-proved
end to end by taking all three backends away and putting them back:

```
svc-a: backend 10.77.1.13 failed (unhealthy)
svc-a: backend 10.77.1.11 failed (unhealthy)
svc-a: backend 10.77.1.12 failed (unhealthy)
svc-a: backend 10.77.1.11 recovered (healthy)
svc-a: backend 10.77.1.12 recovered (healthy)
svc-a: backend 10.77.1.13 recovered (healthy)
```

## HRW: only genuinely unavailable backends move flows

Baseline over three healthy backends: 19 / 17 / 21 across nodea / nodeb / nodec.

| scenario | stable | moved | where they moved from |
|----------|--------|-------|-----------------------|
| one backend down (`10.77.1.12`) | 40 | 17 | **all 17 from nodeb**, 10 to nodea and 7 to nodec |
| one backend down **and** config reordered to `[13,11]` | 40 | 17 | **all 17 from nodeb**, identical to the row above |

The second row is the one worth reading twice. The config edit reordered the
pool while a backend was down, and the survivor mappings came out *identical* to
the outage-only case — the reorder contributed zero movement. On r5 the same
reorder moved 32 of 56 flows. So the two properties hold simultaneously rather
than trading off: health change moves exactly the affected flows, and
configuration change moves none.

## No child or zombie leak

Over 15 health cycles with one healthy and two blackholed backends, sampled
every 5 s: `zombies=0` throughout, `gredist=1` throughout. The two blackholed
`ping` children are observed *live* at the same instant on each cycle, which is
the intended shape — they run concurrently, not one after another, and are
reaped as they finish. In-flight probes are cancelled on `SIGHUP` reload
(the backend array is replaced, so an in-flight index would name a different
backend) and on shutdown, and no stray process survived teardown.

## Regression and teardown

36/36 regressions pass. After the r8 run, `ovs show`, `ovs list-br`,
`ip -br addr`, both route tables and `nft list ruleset` are identical to the
recorded baseline on all three nodes and `ip netns list` is empty.

## Still open

- **F-3** `SIGHUP` frontend change is still a silent blackhole (r9).
- **F-6** forwarding still has no loop detection, so a backend that is reachable
  as another instance's frontend remains an unbounded amplifier.
- Nothing has been published: r7 and r8 both install cleanly and both fail the
  same INSTALL gate. The packager fix is now proven necessary four times over.

---

# Addendum: r9 — SIGHUP cannot blackhole, and the daemon runs as `gredist`

Two coupled fixes. Regression suite **50 pass / 0 fail** (36 r7/r8 unchanged
plus 14 new). The packager INSTALL-stage defect is untouched and remains the
separate build-system blocker; it failed for the fifth consecutive revision.

| | |
|---|---|
| commit | `315f051` |
| recipe | `pkgrel 8 -> 9` |
| build | `buildpkg rc=0`, staged `saphira-gredist-0.1.0-r9` |
| binary | `d7a25b1ee8ef4784…` |
| published | **no**, same INSTALL gate |

## F-3 — the reload blackhole is gone

The defect was structural, not a missing call. A raw socket can be bound
exactly once, so binding the receive socket to the configured frontend baked
that address into the socket for the life of the process; `SIGHUP` replaced the
config and not the socket. `socket()` needs `CAP_NET_RAW` so rebinding is
impossible after the privilege drop, and `bind()` does not need it — neither
option works alone. So the receive socket is now **unbound**, both families are
opened at bootstrap and polled, and the configured frontend is enforced per
packet in userspace. A frontend change is a pure configuration change effective
on the next packet, and it can change family, which the old design could never
do after startup.

Same test, same three hosts, now running as uid 123:

| step | result |
|------|--------|
| control, packet to `10.77.0.11` | `rx=1 forwarded=1` |
| `SIGHUP` to `frontend=10.77.0.21`, packet to `10.77.0.21` | `rx=2 forwarded=2`, **new-address sink received it** |
| packet back to the now-wrong `10.77.0.11` | `rx=3 forwarded=2 not_for_us=1` |

On r7 the middle row was: no counter moved, no backend saw it, no log line. The
third row is the second half of the fix — a packet for the wrong frontend is
now *counted* rather than discarded, so `rx == forwarded + Σdrops` still holds
across a frontend change.

## Privilege drop

Measured before writing it, and the result is why no supervisor is needed.
After `setgroups`/`setgid`/`setuid` to `gredist`:

```
/proc/<pid>/status   Uid: 123 123 123 123   Gid: 123 123 123 123   Groups: 123
                    CapPrm: 0000000000000000   CapEff: 0000000000000000
```

**No capability is retained at all** — not even `CAP_NET_RAW` — and the daemon
proves the drop by requiring `setuid(0)` to fail before it will run. All six
services on all three hosts ran as `gredist`. Forwarding, cross-family
forwarding, the ICMP health probe and `SIGHUP` reload all still work unprivileged,
which is why the design needs no privileged parent and no setcap (which the apk
payload could not carry anyway — there is no xattr channel).

The identity is a compiled-in constant, not a config knob, so an operator who can
edit the configuration cannot redirect the daemon's identity. A missing account
is fatal rather than silently ignored.

### It refuses to start rather than run reload-blind

`/etc/saphira` ships `0750 root:root` — a deliberate decision recorded in r5 — so
a `gredist` user cannot traverse it. Rather than widening the mode as a packaging
side effect, the daemon checks after the drop and exits non-zero naming the fix:

```
gredist: cannot re-read /etc/saphira/gredist/probe.conf as gredist: Permission denied
gredist: Refusing to start rather than run deaf and reload-blind.
gredist: if this is a fresh install, apply: chgrp -R gredist /etc/saphira && chmod 0750 /etc/saphira
```

Verified: exit status 1 with the message; after applying the documented chgrp the
same config starts and forwards. Relaxing `/etc/saphira` is left as an explicit
operator decision.

The `gredist` account itself is created automatically at install by the
packager's accounts.d reconciler — `ensure-identity: user gredist (123:123)
created` — using the same mechanism openssh and saphira-proxyto use. UID 123 is a
fresh reservation; 122 (postgres) was the highest identity already taken.

## Live reload under traffic

Two `SIGHUP` reloads while a client sent continuously, one removing a backend and
one putting it back:

```
before reload : rx=278 fwd=162 mal=13 notus=103     162+13+103 = 278
after 1 reload: rx=388 fwd=217 mal=13 notus=158     217+13+158 = 388
after 2 reload: rx=418 fwd=232 mal=13 notus=173     232+13+173 = 418
4 reloads, 0 reload failures, still owned by gredist
```

Exactly balanced at every step, and the service survived both reloads.

## All r8 and r7 invariants hold, unprivileged

| check | result |
|-------|--------|
| event-loop latency, 3 dead backends | **3 ms** (r8: 3 ms, r7: 5510 ms) |
| HRW baseline, 3 healthy backends | 19 / 17 / 21 across nodea / nodeb / nodec |
| one backend down | 40 stable, 17 moved — **all 17 from nodeb** |
| config reorder `[11,12,13]` → `[13,12,11]` | **57 stable, 0 moved** (r5: 32 of 56 moved) |
| cross-host forwarding, INV-1 | `gap=0` on all six services |
| clean shutdown | `SIGTERM` → 0 processes, 0 zombies, no stray probes |

The "stray ping" count of 2 taken immediately after `SIGTERM` was two in-flight
probe children mid-`SIGKILL`; they were gone on the next sample, and `probes_cancel`
runs on the shutdown path precisely so that is all that can be left.

## Correction to my own tooling

The first r9 accounting run reported `gap=36`, `gap=68` and four other INV-1
violations. The daemon was exactly balanced and the fault was in
`tests/account.py`: its stats regex still had the r6 field list, so the two
counters r7 added (`oversized`, `not_for_us`) were never parsed and never
summed. The daemon was right; the analyser had been silently under-counting for
two revisions. Fixed, and every service then read `gap=0`.

Two further measurement artefacts, both mine and both recorded so the numbers are
readable: `logs-reset` truncates a log while the writer holds a non-append fd, so
the next write lands at the old offset and leaves a NUL hole (`grep` then reports
"binary file matches"); and deleting a backend's address to make it fail, then
re-adding it, leaves any raw socket already bound to that address bound to an
address the kernel no longer has, so a sink started before the delete stops
receiving. Both cost a false "zero deliveries" reading before being tracked down.

## Teardown

`ovs show`, `ovs list-br`, `ip -br addr`, both route tables and `nft list ruleset`
are identical to the recorded baseline on all three nodes; `ip netns list` is
empty. The `gredist` account and the installed r9 package are left in place — both
are the packaged service identity and the artefact under test.

## Still open

- **F-6** forwarding still has no loop detection: a backend reachable as another
  instance's frontend remains an unbounded amplifier.
- Nothing is published. r7, r8 and r9 all build, install cleanly and fail the same
  INSTALL gate. The packager fix is now proven necessary five times over.

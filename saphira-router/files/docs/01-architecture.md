# D1 — Architecture

Status: **design, not implementation.** No code is written against this document
until it is signed off. Where this document states a fact about an existing
Saphira component, that fact was read out of the tree, not assumed.

---

## 1. What saphira-router is

`saphira-router` is the Saphira Linux **multi-tenant control plane** for load
balancing, routing, virtual networking and managed nodes.

It is a *platform*, not a collection of configuration editors. The distinction
is load-bearing and is tested in §4:

> A load-balancer administrator operates the platform without opening a
> browser and without hand-editing generated configuration.

The organising decision, and the one that keeps this from becoming six
unrelated admin screens, is stated in §7.3: **a virtual service is a service
object; which renderer implements it is deployment policy.**

### 1.1 What it is not

- Not a dashboard. Not a SaaS product. Not web-hosted.
- Not a replacement for the component CLIs — it is the plane *above* them.
- Not a config-file manager. It renders, validates, activates and verifies;
  it does not let an operator hand-maintain what it generates.

---

## 2. Interface hierarchy

```
                    saphira-router core
                           |
                     common API / IPC
                      /             \
                  TUI                CLI --json
           primary human          automation
            interface              interface
                      \             /
                       [ web — later, optional ]
```

| Surface | Role | M1 |
|---|---|---|
| **TUI** | Primary human interface. Acceptance criterion. | **Required** |
| **CLI** | First-class automation surface, machine-readable `--json`. | **Required** |
| **API / IPC** | The single control surface beneath both. Never privileged-only. | **Required** |
| **Web** | Future optional module/client consuming the same description layer. | **Explicitly deferred** |

**The TUI is the acceptance criterion for M1.** An M1 that merely has a
working API is *not accepted*. See §4.

Web support is a future optional client. It is not part of M1 acceptance, and
nothing in D1–D4 depends on it existing. The design keeps it cheap: §6.4
describes a declarative description layer that a web client could consume
without redesigning providers — but nothing in the core or the ABI may
*require* it.

### 2.1 No privileged operation exists only in the TUI

The TUI and the CLI are peers over the same API/IPC. Every operation
available in the TUI is available to the CLI, and therefore to automation.
There is no "TUI-only" administrative capability. This is a hard rule, and it
is what makes the platform scriptable and testable.

Conversely, the CLI's `--json` output is the contract that automation depends
on, so it is specified in D9 (`interfaces.md`) rather than left implicit.

---

## 3. The three-part split

### 3.1 Core daemon (`saphira-router`)

A single long-running service that owns all state and all authority:

- authentication and Argon2id password verification
- tenants, users, roles, capability checks
- the SQLite database and **desired state**
- **observed state** collection and storage
- the **audit** trail
- the **configuration transaction / rollback** engine
- the **API/IPC** server
- the **module registry** (load, capability negotiation)
- **node/drone transport** (enrollment, dispatch to managed hosts)
- the **secrets** store
- the **event/status** system

The core owns the database handles. No module ever receives one (§D2, D3).

### 3.2 API / IPC

The one control surface. The TUI and CLI are clients of it. Transport and
protocol are specified in D9; the architectural constraints here are that it is
**local by default** (Unix domain socket) and that no privileged operation is
reachable by any path that bypasses it.

**One authority for writes.** The core is the only writer of persistent state.
Neither the TUI, the CLI, a drone, a module, nor an observer opens the
database; everything is submitted over IPC and applied by the core-owned state
service (D2 §5, D4 §1).

```
TUI ─┐
CLI ─┼── IPC ──> core ──> SQLite
     │
observer/module callbacks ──> core services ──> SQLite
```

This is a security boundary rather than a style rule. If any client could open
the database and write it, RBAC, the audit trail, the transaction engine and
the desired/observed separation would all be bypassable by anyone who could
reach the file. One write authority is what makes those invariants mean
anything.

### 3.3 TUI and CLI

- **TUI** — full-screen terminal interface built on ncurses. It is a *client*.
  It renders what the core tells it and submits operations back. It does not
  talk to components, and it does not touch the database.
- **CLI** — a thin client of the same API. `--json` on every read and write
  command.

The TUI's rendering is **owned by the TUI layer**, not by modules. Modules
describe; the TUI draws. This is what makes the interface consistent and what
leaves a future web client free to consume the same description (§6.4).

### 3.4 Managed hosts / drones

`nodea`, `nodeb`, `nodec` and any enrolled host run a **drone**: a small agent
that executes dispatched operations on the host and returns results. The drone
holds no policy. It is told what to do by the core, over the node transport,
and it reports observed state back. The drone is the boundary at which
controller authority stops and host execution begins — and, per §8, the place
where a privileged operation is actually performed.

---

## 4. M1 acceptance is judged in the TUI

M1 is **not** accepted because the API works. From the TUI, an operator must
be able to do all of the following. Each row names the document that specifies
it, so acceptance is traceable to a spec rather than to an impression.

| # | Operator capability | Specified in |
|---|---|---|
| 1 | Log in and select tenant / context | D3 (auth, sessions), D9 |
| 2 | See controller and managed-host status | D1 §7, D7 (state) |
| 3 | Enroll / view hosts and their discovered capabilities | D6 (enrollment) |
| 4 | Create / edit / remove a virtual service | D4 (schema), D8 (txn) |
| 5 | Add / remove / enable / disable / **drain** real servers | D4, D7 |
| 6 | Select and configure IPVS + ldirectord | D1 §7, D4, Appendix A |
| 7 | Configure basic HAProxy L4 / L7 services | D1 §7, D4, Appendix A |
| 8 | Inspect / edit the HAProxy ACL, rule and rewrite objects M1 supports | D1 §7.4, D4 |
| 9 | Manage gredist services | D4, Appendix A |
| 10 | Inspect / manage OVS bridges, ports, VLANs | D4, Appendix A |
| 11 | Configure / view PPPoE | D4, Appendix A |
| 12 | See **desired state separately from observed health** | D7 |
| 13 | Validate a change **before** applying it | D8 |
| 14 | Apply it | D8 |
| 15 | See success / failure, and *why* | D8, D1 §10.2 |
| 16 | Inspect audit history | D4 (`audit_event`), D9 |
| 17 | Roll back a previous transaction | D8 |

Acceptance is: an operator can complete all seventeen **from the TUI alone**,
without a browser and without editing generated files by hand.

---

## 5. Core-owned services

The core owns only common platform services. Anything technology-specific is a
module (D2). The list is exhaustive by intent — adding a technology must not
require adding to it.

```
authentication / Argon2id          node / drone transport
tenants / users / RBAC             secrets
database and desired state         event / status system
observed state
audit
transactions / rollback
API
CLI plumbing
module registry
```

---

## 6. Module boundary

### 6.1 Providers

Technology-specific functionality lives in separately built, independently
packageable `.so` modules:

```
mod_ipvs.so        mod_ovs.so          mod_import_f5.so
mod_ldirectord.so  mod_pppoe.so
mod_haproxy.so     mod_bind9.so
mod_gredist.so     mod_libvirt.so
mod_import_loadbalancerorg.so
```

Later additions such as `saphira-udpdist` are **installable additions**, not
a core change. See D2 for the full contract, the versioned ABI, and the design
test that proves it.

### 6.2 Packaging

```
saphira-router                  core; usable with no modules at all
saphira-router-ipvs
saphira-router-ldirectord
saphira-router-haproxy
saphira-router-gredist
saphira-router-ovs
saphira-router-pppoe
saphira-router-bind9
saphira-router-libvirt
saphira-router-import-loadbalancerorg
saphira-router-import-f5
```

Installing `saphira-router-haproxy` makes HAProxy functionality **appear** in
the TUI. Removing it makes that functionality **disappear cleanly**, without
breaking the rest of the TUI. The TUI derives its sections and actions from the
module registry; it does not hard-code a provider list.

### 6.3 Capability negotiation is a core concern, not a UI one

A host advertises capabilities (D6). The core refuses to deploy an object
requiring a capability the target does not have. This is a *core* decision
recorded in state and audit — not a TUI nicety — because it must hold for
automation exactly as it holds for a human.

### 6.4 The description layer (why a future web client is cheap)

Modules may not draw terminal UI. They **describe** — object types, fields,
actions, and their capabilities — and the TUI renders that description
generically. The same description is what a future web client would consume.

This is the seam that keeps the deferred web path open without designing for
it now. See D2 for the `describe` operation.

---

## 7. The domain model

### 7.1 Shape

The full object list, its namespacing, and its storage are specified in D4.
The architecture-level rules are:

- **Core objects** describe *intent*: Tenant, User, Role, Host, Cluster,
  Network, Bridge, Interface, VLAN, PPPoESession, VirtualService, RealServer,
  HealthCheck, LoadBalancer, and the provider-native objects.
- **Modules** are *implementations* of those intents, where a module
  implements them.
- The two are related by **renderer policy**, not by inheritance.

### 7.2 The simpler common abstraction is preserved

An ordinary service must not require understanding provider internals. A
`VIP` is the everyday view —

```
VIP: address, port/protocol, algorithm, healthcheck, RIPs
```

— and it is a **projection** over `VirtualService` + `RealServer` +
`HealthCheck`, not a separate competing model. A simple service is expressible
without touching any provider-native object.

### 7.3 The decision that prevents six unrelated admin pages

> A VIP with three RIPs is **a service object**. Whether its renderer is
> IPVS/ldirectord, HAProxy, or eventually udpdist is **deployment policy**.

`VirtualService`, `RealServer` and `HealthCheck` are control-plane objects.
IPVS, HAProxy and future modules are **renderers** of those objects. The
service model does not change when the renderer does.

This is why the platform can grow into a real load-balancer platform instead
of becoming six unrelated configuration pages glued together: the common model
is the product, and renderers are interchangeable implementations of it.

### 7.4 Provider-native objects are allowed, and are namespaced

Where the common abstraction is insufficient, native provider objects remain
possible — HAProxy ACLs, request/response rules, rewrites — **without
contaminating unrelated modules**. They live in a module-owned namespace
(D4), they are rendered by their owning module, and removing that module
retires them without touching core objects.

HAProxy is deliberately **not** reduced to a small VIP/RIP abstraction. The
model must support L4 and L7, ACLs, maps, stick tables, request/response rules,
rewrites, TLS, health checks and routing rules. An advanced/raw escape hatch
exists for directives the structured model does not yet understand, so that
they are never silently destroyed on the next save (D4, D8).

---

## 8. Process and privilege model

**The core runs unprivileged wherever possible.** This is deliberate and is
*not* an inherited daemon pattern. Unlike gredist and proxyto — which must
start as root to open a raw socket or bind a privileged port — the
**controller itself needs no privileged socket and no hardware access.** It
should never be given a reason to run as root.

The rule, stated generally:

1. **Unprivileged by default.** The core, the TUI and the CLI run as an
   ordinary unprivileged service identity.
2. **Minimum necessary privilege, at the narrowest boundary.** Any component
   that genuinely requires privilege gets it at the helper or drone boundary
   — a narrowly scoped process on the host that needs it — **not** by
   escalating the controller.
3. **Drop permanently where the design permits.** Where a component must
   start privileged, it drops immediately to its own identity and verifies the
   drop, following the existing gredist / proxyto precedent.
4. **Do not inherit a daemon privilege pattern where it is unnecessary.**

Per-component privilege facts, read from the tree, are in Appendix A. In
summary: gredist needs `CAP_NET_RAW`; two of the packaged health checks
(`gre`, `ipproto`) also need it; ldirectord and virtqemud are root by
upstream design. None of that is a reason for the *controller* to be root.

---

## 9. Saphira conventions this design inherits

- **Dual init.** A package that ships a daemon ships **both** an OpenRC script
  (`/etc/init.d/<name>`) and a systemd unit
  (`/usr/lib/systemd/system/<name>.service`).
- **Ship both, enable neither.** Nothing is enabled or started at install.
  Enabling is a *profile* decision. A router that must be on by default is
  added to a profile, not to a recipe.
- **Config location.** `/etc/saphira/<component>/<name>.conf`, installed
  `0750 root:root`; flat `KEY=VALUE` for Saphira-original daemons. A daemon
  that self-drops must verify its own config is still readable and refuse to
  start, naming the group change it needs.
- **Service identity.** `files/accounts.d/<pkgname>`. The UID/GID namespace is
  operator-locked: `0..100` system, `101..999` services, `1000+` human,
  `65534` nobody.
  `122` (postgres), `123` (gredist), `124` (hostapd), `125` (frr) and `126`
  (breathgslb) are taken; `127+` are free and are where saphira-router should
  allocate.
- **Non-merged `/usr`.** `/bin`, `/sbin`, `/usr/bin`, `/usr/sbin` and
  `/lib` vs `/usr/lib` are distinct. No usrmerge compat symlinks.
  `/lib64` and `/usr/lib64` are forbidden.
- **Headless.** No X11/Wayland/GTK/Qt/display manager, ever. A TUI over a
  terminal is not a graphical stack.

### 9.1 Intended dependency set

Small and musl-friendly; no new bootstrap. Chosen from what Saphira already
packages and already exercises:

| Need | Choice | Why |
|---|---|---|
| Language | **C11** | core daemon, SQLite, Argon2id, proper TUI, installable `.so` providers |
| Persistent state | **SQLite** | present, musl-safe, single-file rollback/history store |
| Passwords | **libargon2** (argon2id reference impl) | already packaged and used by `openldap`, `php85` |
| TUI | **ncurses** (wide) | already packaged; ships `libncursesw`, `libformw`, `libmenuw`, `libpanelw`, terminfo |
| JSON | **json-c** | packaged and widely exercised (bind, clamav, frr, freeradius, libvirt, syslog-ng); a parser for a multi-tenant control plane is not something to hand-roll |

Go is **not** adopted. It is absent from the current host and adopting it to
make HTTP/JSON convenient is the wrong trade for this project.

---

## 10. What the router does about the components underneath it

### 10.1 The router does not repair its dependencies

This project must not quietly fix every daemon beneath it. If a component is
missing a surface the router needs, the router:

- **documents the surface it needs** (Appendix A),
- **reports the gap to the operator, plainly** (§10.2),
- and leaves the fix to that component's own package task.

### 10.2 Expose gaps brutally

The router is the first place these limitations become visible to an operator
across the fleet, and it must say so rather than paper over it. Examples the
platform is expected to be able to emit:

- `HAProxy observed state unavailable: runtime socket not configured`
- `ldirectord target cannot validate safely; activation requires restart`
- `gredist has no service integration; managed by the router drone directly`

A control plane that hides its own blind spots is worse than no control plane,
because the operator stops looking. Gap reporting is a first-class behaviour,
not a diagnostic afterthought.

### 10.3 Relationship to the existing "no dashboard" position

`saphira-network`'s OVS proposal states a house position: *"No dashboard in the
loop; the commands are the product."* That position is **upheld** — there is
no dashboard here, and none is planned. What changes is that the router adds a
**terminal** interface over the same model, and deliberately reuses the
component CLIs rather than replacing them. This is recorded as a deliberate,
documented extension of that position, not a contradiction of it.

---

## Appendix A — Component surface contracts

For each component, what `saphira-router` needs, and what actually exists.
**All of this was read from `/recipes` and the acceptance nodes; none of it is
assumed.**

### A.1 LVS / ldirectord

- **Where it lives:** there is **no `ldirectord` package**. `ldirectord` ships
  inside `/recipes/resource-agents` (ClusterLabs resource-agents). The package
  is `resource-agents`; the binary is `ldirectord`. Any design assuming a
  `saphira-ldirectord` package is wrong.
- **Control surface:** a config file and a subcommand CLI. Accepted
  subcommands are `start stop status restart try-restart reload force-reload`
  — **there is no validate/dry-run mode.** Reload is SIGHUP. A pid file is
  written under `/var/run` named from the config basename.
- **Saphira's patches:** four, and they are portability/correctness fixes, not
  features — making Socket6 optional (perl has no Socket6, so upstream cannot
  compile), a `HTTP::Tiny` check fallback, bracket-aware IPv6 parsing, and
  IPv4-mapped IPv6 literals. **No new API, socket, CLI verb or config keyword
  is added by Saphira.** Model the real surface, not upstream's feature list.
- **Consequence for the router:** validation cannot be delegated to the daemon
  (D8 records the safe substitute); activation is a restart, not a reload, for
  changes that add or remove a virtual server block.
- **Open requirement:** the router must know the `execute=` / `fallbackcommand=`
  / `checkcommand=` hook surface, because health checks and drain are expressed
  through it.

### A.2 HAProxy

- **Control surface:** `haproxy -c -f` validates; SIGHUP/USR2 reload path
  exists. The Runtime API is compiled in and documented in the shipped
  `management.txt`, but **no shipped Saphira config enables a `stats socket`.**
- **Consequence for the router:** with no runtime socket there is **no
  observed-state path** for HAProxy. The router must report this rather than
  infer health. Enabling the socket is a haproxy-package change, out of scope
  here.
- **Open requirement:** the router needs a runtime API (stats socket) for
  observed state and for per-server `maint`/`drain`; and it must round-trip
  advanced directives (D4 escape hatch).

### A.3 saphira-gredist

- **Control surface:** config file, SIGHUP to reload, and a stats/introspection
  path that is **not** a socket. It ships **no service integration** (no init
  script in its recipe).
- **Consequence for the router:** gredist is managed by the router drone
  directly, and its observed state comes from whatever signal-based
  introspection exists, not a queryable endpoint. Its unpublished revisions
  (below) mean a router cannot yet deploy a gredist module against a known
  package.
- **Open requirement:** a queryable status surface, and a service definition so
  a node's gredist instance is discoverable and restartable.

### A.4 saphira-network / OVS

- **Control surface:** real and good. `ovs-vsctl` against OVSDB, plus
  `ovs-appctl` / `ovs-ofctl` and a local UNIX socket. This is the one component
  with a genuine queryable API today.
- **Consequence for the router:** topology must be read from live OVS state,
  never inferred from stored config (the brief is explicit, and the component
  supports it).
- **Open requirement:** the existing `OVS_PROPOSAL.md` is a *roadmap*, not
  implemented behaviour; the router builds on the real `ovs-vsctl` surface, not
  on the proposal.

### A.5 rp-pppoe

- **Control surface:** **none of its own.** It is explicitly *not* a service
  package; its helpers are driven per configured session by `pppd`. It ships
  client-side service files for its server/relay/sniff roles, but the client
  path is pppd-driven.
- **Consequence for the router:** PPPoE is a managed **networking primitive**,
  not a command textbox. "Activating" PPPoE means managing a pppd session and
  its lifecycle, not starting a daemon. The transaction model in D8 must
  accommodate a primitive that has no validate-then-activate-daemon shape.
- **Security requirement:** PPP credentials must never be returned through
  ordinary API responses (D3).

### A.6 BIND9

- **Control surface:** `named-checkconf -z` is a genuine read-only validator,
  and `rndc` over `127.0.0.1:953` with a TSIG key is the real control surface.
  **No `rndc` config or key is shipped by the package.**
- **Consequence for the router:** the router must provision the TSIG key as a
  secret before it can drive `rndc`, and must validate zones before reload.
  DNS is represented in the model now (D4) so the schema does not paint us into
  a corner, but it does not block the first working load-balancer control
  plane.
- **Open requirement:** shipped rndc provisioning; zone revision/audit history
  is a router-side responsibility (D4).

### A.7 libvirt / virsh

- **Control surface:** good and rich. `virsh` and the per-daemon UNIX sockets
  under `/run/libvirt`; `virtproxyd` for remote TLS.
- **Consequence for the router:** represented in the model now; M1 does not
  build a virt-manager replacement. M1's need is enough VM management to
  attach workloads to Saphira networking and load balancing.
- **Security fact, carried into D3:** libvirt is built **polkit-disabled**,
  and the daemon ships with **no access control on `virtqemud`**. Remote
  access needs TLS certs that are *not* provisioned by the package. The router
  must treat VM operations as a distinct, high-privilege capability class.

### A.8 saphira-lb-healthchecks — a shared first-party capability

- This is a **shared first-party capability the router selects and
  configures.** The router does **not** reimplement it. Its check interface is
  already documented and already matches ldirectord's external-check contract
  (five positional arguments), so the router and the LB components can share
  it directly.
- Two of its checks (`gre`, `ipproto`) require elevated privilege; the router
  must account for that in its privilege model (§8, D3).

### A.9 saphira-proxyto

- Confirmed a plain TCP front proxy with **no API, no socket, no stats**. Not a
  control-plane component; not a router target.

---

## Appendix B — External prerequisites (recorded, NOT fixed here)

These are gaps in the *component* packages. They are **owned by those
packages' own tasks**, not by this project. `saphira-router` documents the
surface it needs (Appendix A) and reports the gap to the operator (§10.2).

| # | Component | Gap | Router consequence |
|---|---|---|---|
| 1 | `resource-agents` | **pkgrel drift** — payload changed while `pkgrel` stayed the same, so the published package is stale | ldirectord behaviour on a node may not match the tree; surface must be re-confirmed per node |
| 2 | ldirectord (OpenRC) | service `status` calls an **invalid subcommand** | service state cannot be trusted via the init script |
| 3 | ldirectord (systemd) | **wrong `PIDFile`** | systemd process tracking is broken; activation/restart via the unit is unreliable |
| 4 | HAProxy | **no stats/runtime socket configured** | **no observed state** for HAProxy; health must be reported unavailable, not guessed |
| 5 | `saphira-gredist` | **unpublished revisions** (tree ahead of repository) | a router module cannot yet target a published gredist package |
| 6 | `saphira-gredist` | **no service integration** | no init definition; router manages the process via its drone |
| 7 | `saphira-lb-healthchecks` | **packaged but not wired into any config** | the check library ships unused; the router is the natural first consumer |

Recorded consequences, in the router's own terms: **HAProxy observed state is
unavailable until #4 is fixed by the haproxy package**; **ldirectord cannot
validate safely and needs #2/#3 fixed by resource-agents before its service
surface is dependable**; gredist is managed by drone until #5/#6 are fixed by
that package.

---

## Appendix C — M1 acceptance topology (address-level)

Per direction, the controller/test host is **left unresolved** and not guessed.

- **Acceptance managed nodes** (known addresses, verified reachable from the
  build host):
  - `nodea` — `172.16.7.100`
  - `nodeb` — `172.16.7.110`
  - `nodec` — `172.16.7.120`
  - All are Saphira-D Linux 0.2, `x86_64`, systemd.
  - Currently present: `openvswitch`, `saphira-gredist`, `saphira-network`
    (so `ovs-vsctl` and `gredist` are available).
  - Currently **absent**: `ipvsadm`, `resource-agents` (ldirectord),
    `haproxy`, `rp-pppoe`, `bind`, `libvirt`.
  - The absence is useful: it is a live demonstration of the capability-
    negotiation model — the router must refuse to deploy a VIP requiring
    `ldirectord` onto a node that does not have it (D6).

- **Controller / test host:** **unresolved, deliberately.** `hatchling` and
  `hatched` are both real hostnames *and* both the names of package repository
  locations in existing Saphira usage; no address has been supplied and none
  is guessed. The controller host is a **configurable parameter** of the M1
  acceptance run. When an address is supplied, it is recorded here.

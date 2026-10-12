# D3 — Security model

Status: **design, not implementation.** Companion to D1 and D2. This document
defines the **security boundary** that D1 and D2 assume. It is written to be
honest about what in-process modules are and are not, because overclaiming
there is the specific failure this document exists to prevent.

---

## 1. Threat summary

A multi-tenant control plane that (a) holds long-lived credentials, (b) writes
live configuration for network daemons, (c) executes on remote managed hosts,
and (d) loads provider code, has four distinct trust boundaries. They are
listed, then treated in turn.

| # | Boundary | Trust position |
|---|---|---|
| 1 | Human ↔ TUI/CLI | **untrusted input**, authenticated identity, scoped authority |
| 2 | TUI/CLI ↔ core API/IPC | **local** transport, authenticated, the single authority point |
| 3 | Core ↔ module (`.so`) | **trusted first-party code, same process — NOT a sandbox** |
| 4 | Core ↔ managed host (drone) | **remote execution** over a re-authenticated channel |
| — | Component daemons (ldirectord, HAProxy, OVS, gredist, BIND, libvirt) | **outside the control plane's trust**; the router reports on them, does not trust them |

The load-balancing plane's own data (VIPs, RIPs, networks) is untrusted in the
sense that it can cause the platform to write configuration that changes real
traffic — which is why every write is a reviewed, validated, transactional
operation (D8), not a direct edit.

---

## 2. The in-process module boundary, stated honestly

D2 forbids a module from holding a database handle, from authenticating, from
reading a secret directly, and from writing state or audit directly. It
requires a module to obtain those through the **core-mediated services** in
its `sr_ctx`.

That is the **supported path**. It is the correct design, and it keeps module
code honest, reviewable and consistent.

**But this document will not claim that an in-process `.so` "can never bypass
RBAC."** It can. A trusted C module running in the same address space as the
core can technically reach process memory, make arbitrary syscalls, and open
files. No ABI in the same process makes that impossible. Saying otherwise
would be a false security claim, and a false security claim in a document
whose entire job is to state the boundary is worse than no document at all.

So, precisely:

- **A `.so` module is trusted first-party code that shares the core process.
  It is not a sandbox boundary.** Its correctness is a code-review and CI
  matter, not a runtime-isolation matter.
- **The ABI makes the correct path the easy, supported, and only-documented
  one** (no DB handle is ever passed; services are the interface). A module
  that reaches around it is a bug or an attack by a trusted party, and is
  treated as such — not as something the ABI was supposed to prevent.
- **Real isolation requires a process boundary.** A future helper-process
  module (D2 §7, §11) is what genuinely confines a provider. The ABI is
  deliberately narrow and data-oriented so that move is possible later without
  changing the domain or API contract — but that is a *future* option, not a
  property of today's in-process design.

The security boundary that exists **today** is between *unauthenticated or
under-privileged input* and *core-mediated state change*. Modules are trusted
and inside it, not across it.

### 2.1 One authority for writes

The core is the only writer of persistent state. The TUI, the CLI, drones,
modules and observers all submit through IPC to the core-owned state service
(D1 §3.2, D4 §1); none opens the database.

This is stated here because it is a **security control, not a convention**.
RBAC (§4), the audit trail (§6) and the desired/observed separation (D7) are
all enforced inside the core. If any client could write the database directly,
every one of those invariants would be bypassable by anyone able to reach the
file — and the platform's tenant isolation would be a claim rather than a
property. Keeping the write surface closed to exactly one component is what
makes "RBAC is enforced" a fact about the system rather than a claim about
client behaviour.

---

## 3. Authentication

- **Passwords: Argon2id only.** Via the packaged `libargon2` (the reference
  implementation). No plaintext storage, no reversible passwords, no
  application-rolled hash. If Argon2id parameters must change later, they are
  versioned with the stored hash and re-hashed on next successful login.
- Parameters (memory cost, time cost, parallelism, salt length) are
  configurable but have a floor; a stored credential whose parameters fall
  below the floor is rejected and must be re-registered.
- **Sessions are scoped to (user, tenant).** A session token is bound to one
  user *and* one tenant context; it is not a bearer token for the whole
  platform. Switching tenant context is an explicit, audited action that
  re-checks authorization against the new tenant.
- **The TUI and CLI authenticate identically.** There is no "trusted local
  user" shortcut that skips auth because the transport is a local socket.

---

## 4. Authorization

- **Explicit capabilities, not an implicit admin-everything role.** The
  capability set is defined up front (D5) and admin is a *named set* of
  capabilities, not a wildcard that silently equals every future permission.
  Adding a new privileged operation requires adding a new capability; existing
  roles do not silently gain it.
- **Tenant isolation is a hard invariant**, enforced at the service layer on
  every state read and write: a query is always implicitly scoped to the
  session's tenant. There is no code path that reads across tenants without an
  explicit, audited, privileged operation.
- The same authorization service is what the TUI, the CLI, and **modules** all
  call (D2 §5). A module action is authorized as the acting user against the
  capability the operation requires — a module being loaded grants no
  authority.

---

## 5. Secrets

- **Stored separately from ordinary configuration.** A separate store
  (D4) with its own file, its own permissions, and its own access rules — a
  secret is not a config row an operator can read through the normal API.
- **Never returned through ordinary API responses.** Reads yield a
  **reference** (D2 §5), not a value. The TUI and CLI show that a credential
  *exists*, never its plaintext. This covers PPPoE credentials (D1 A.5) and
  BIND TSIG keys (D1 A.6) specifically.
- Encryption at rest uses a key the store does **not** contain; the design
  assumes a key-encryption-key supplied by the deployment (file or agent), so
  database theft alone does not yield plaintext credentials.
- Modules receive secret **references** through the core service and cannot
  read the secret store directly.

---

## 6. Audit

- **Every configuration change is audited**: who (user, session, tenant), what
  (object, operation), before/after, outcome, and the originating transaction
  id where applicable. D4 defines the `audit_event` table; D9 exposes the read.
- Read access to sensitive configuration and any secret-adjacent operation is
  also recorded, so "who looked at what" is answerable.
- The audit trail is **append-only** in intent: it is the forensic record and
  is not edited by normal operations. Retention and its own tamper-evidence
  are implementation-time decisions recorded here as intent.

---

## 7. Node enrollment and the remote boundary

Enrollment (D6) is the highest-risk remote operation, because it converts an
unknown machine into a managed one.

- Initial enrollment is **out-of-band and human-gated**: an operator
  authorises a host, and enrollment presents material that is bound to that
  host's real key (a proof over its identity key), not a bearer token that
  anyone could replay.
- The node's identity after enrollment is its **key**, and the channel is
  re-authenticated, so a compromised enrollment token alone does not yield a
  lasting foothold.
- Discovery is treated as **untrusted input**: package inventories, version
  strings and reported capabilities from a host are parsed defensively and
  never trusted to authorise an action on their own. The core decides what a
  host may host based on its own policy, not the host's self-report alone.
- The drone executes what the core dispatches. A compromised node can only
  affect itself and what it is asked to do — it cannot, by design, reach the
  core's database or other tenants (D1 §3.4, boundary 4).

---

## 8. Per-component privilege, honestly

Read from the tree; the router's job is to *use* these correctly, not to
re-architect the components.

| Component | Privilege reality | Router's obligation |
|---|---|---|
| gredist | needs `CAP_NET_RAW`; self-drops to its own uid | perform any raw-socket work in the narrowest helper/drone boundary; the **controller** stays unprivileged |
| lb-healthchecks | two checks (`gre`, `ipproto`) need `CAP_NET_RAW`/root | run those checks in a restricted probe context, never in the core process |
| ldirectord | root by upstream design; shells out to `ipvsadm` | treat as a remote effect on the node; the core never runs it locally |
| virtqemud (libvirt) | **polkit-disabled → no access control on the daemon** | treat VM operations as a distinct, high-privilege capability class; the router must not become a confused deputy handing tenants VM control it does not itself restrict |
| BIND | drops privileges via `-u`/systemd `User=` | the router's `rndc` access is via a provisioned TSIG secret (D1 A.6) |

The controller itself needs **no privileged socket and no hardware access**
(D1 §8), so it runs unprivileged. Anything a component needs beyond that is
granted at the helper/drone boundary, minimally and temporarily, and dropped
permanently where the component's design allows.

---

## 9. Honest gap reporting as a security property

D1 §10.2 requires the router to surface component limitations rather than hide
them. That is also a security property: an operator who cannot see that
"HAProxy observed state is unavailable because no runtime socket is
configured" may wrongly trust a health view. So the platform treats gap
reporting as a first-class behaviour — a health or capability that cannot be
determined is reported as **unavailable/unknown**, never optimistically
healthy, and never silently omitted.

---

## 10. What this model does not claim

Stated plainly, to be quoted by future reviewers:

- It does not claim in-process `.so` modules are isolated (§2). They are
  trusted first-party code; real isolation is a future helper process.
- It does not claim the control plane is hardened against a malicious
  *node* beyond that node's own blast radius.
- It does not claim a component's own privilege model is sound (e.g. libvirt
  ships with no access control) — it only requires the router to not make that
  worse by becoming an unconfined deputy.
- It does not treat a health check that cannot run as a passing check.

These boundaries are the honest ones. The design's job is to state them, not
to paper over them.

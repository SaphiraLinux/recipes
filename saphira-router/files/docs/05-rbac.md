# D5 — Permission model

Status: **design, not implementation.** Companion to D1–D4. Read D1 §5 and D3
§4 first — this document specifies the capability set those invoke.

---

## 1. Principles

1. **Capabilities are explicit and namespaced.** Authority is a set of named
   capabilities, not a property of a role name, not a verb on a resource, and
   never a wildcard.
2. **Deny by default.** Absence of a grant is a denial. There is no
   permissive default, no implicit union, and no "everything except".
3. **`admin` never implies a future capability.** When a new capability
   arrives — a new module, a new operation — it is **inert** until it is
   explicitly granted. §5 specifies the mechanism and the test that proves it.
4. **Tenant isolation is a hard invariant,** enforced on every access, and
   covered by negative tests (§7) rather than asserted.
5. **The TUI and the CLI are judged identically.** The interface an operator
   happens to use cannot widen their authority.

---

## 2. Capability naming

Capabilities are `domain.resource.verb` for core objects and
`module.resource.verb` for provider-native objects. A module may only mint
capabilities inside its own namespace; the core reserves the unprefixed
domain.

```
# Core — identity and platform
tenant.create            tenant.read              tenant.manage
user.create              user.read                user.manage
role.create              role.read                role.grant
host.enroll              host.read                host.manage
cluster.read             cluster.manage
audit.read               audit.export
transaction.read         transaction.apply        transaction.rollback
secret.read              secret.manage
module.read

# Core — networking
interface.read           interface.write
bridge.read              bridge.write
vlan.read                vlan.write
network.read             network.write
pppoe.read               pppoe.write              pppoe.credential.read

# Core — the common service model
loadbalancer.read        loadbalancer.write
virtualservice.read      virtualservice.write
realserver.read          realserver.write
realserver.drain         realserver.maintenance
healthcheck.read         healthcheck.write

# Core — platform administration
firmware.read            platform.upgrade         platform.shutdown
diagnostics.read         drone.deploy             drone.restart
```

Module-owned namespaces (created by the module's own `describe` output, D2
§4.1, and granted exactly like any other capability):

```
haproxy.acl.write        haproxy.rule.write       haproxy.rewrite.write
haproxy.map.write        haproxy.sticktable.write haproxy.frontend.write
ovs.bridge.write         ovs.port.write           ovs.tunnel.write
gredist.service.write    ipvs.virtual.write       ipvs.real.write
dns.zone.write           dns.record.write         libvirt.vm.write
libvirt.vm.power         libvirt.pool.write
```

Two consequences of namespacing:

- A module that is **absent** has no capabilities, so there is nothing to
  grant and nothing to attempt. Removing `saphira-router-haproxy` removes
  `haproxy.*` from the effective set without touching any role (D2 §8).
- Two modules cannot collide, because a module cannot mint capabilities
  outside its own prefix. The core rejects a module whose `describe` output
  claims a capability in another's namespace.

### 2.1 Verb discipline

Read verbs (`*.read`) are distinct from write verbs. `realserver.drain` and
`realserver.maintenance` are separated from `realserver.write` because taking
a real server out of rotation is a distinct operational authority from editing
its definition, and some tenants will want exactly that split. Capability
design should split wherever two operations have materially different risk.

---

## 3. Roles are named capability sets

A role is a *named set* of capabilities, optionally scoped to one tenant
(D4 §4). It carries no implicit meaning:

- `admin` is a role that happens to be granted a specific, enumerated list of
  capabilities. It is not a wildcard, not a superuser bit, and not consulted
  as a special case anywhere in the authorization path.
- A role with no capabilities grants nothing. This is legal and useful (an
  intentionally inert role is a valid thing to have).
- System roles (`tenant_id IS NULL`) may be assigned across tenants; tenant
  roles are assigned only within their tenant.

**Authorization never inspects the role name.** The check is always
"is capability X in the effective set for this (user, tenant)?" That is what
makes §3's first bullet true by construction rather than by discipline.

---

## 4. Tenant isolation

Tenant isolation is enforced in **one place**: the state service that every
read and write passes through (D2 §5, D1 §3.2).

- Every tenant-scoped table carries `tenant_id` (D4 §1.1) and every query is
  implicitly scoped to the calling session's tenant. A missing `tenant_id`
  predicate is a bug, and §7 is designed to catch it.
- A session is bound to one `(user, tenant)` pair (D3 §3). Changing tenant
  context is an explicit action that re-authorizes against the new tenant and
  is audited; it does not widen the session's grant.
- **Cross-tenant access has no legitimate path through the normal API.** Where
  a genuinely global operation exists (enumerating the tenants an
  administrator may see), it is a distinct capability operating over a
  distinct data path, not a filter that can be forgotten.
- Bindings and provider instances are tenant-scoped like everything else
  (D4 §6.1), so a binding cannot be used as a lever across tenants.

---

## 5. New capabilities are inert by default

This is the mechanism behind "admin must never imply future capabilities", and
it is worth stating concretely because it is easy to get wrong.

When a new capability row appears in the `capability` table — from a new
module, a new operation, or a migration:

1. **No role gains it.** Existing role grants are explicit rows in
   `role_capability` (D4 §4); a new capability with no matching grant row is
   simply absent from every role.
2. **No code path treats an unknown capability as permitted.** The
   authorization check is a lookup; a miss is a denial. There is no
   "well-known" or "default" set that could absorb it.
3. **It becomes usable only when granted** to a role, and that grant is
   itself an auditable action subject to `role.grant`.

So an operator with a fully-loaded `admin` role, running a controller whose
core has just learned a new module, cannot perform that module's operations
until someone with `role.grant` says so. The new surface appears in the TUI
because the module registered it (D1 §6.4), but it is **not operable**, and the
TUI shows it as capability-denied rather than hiding it or pretending it works.

---

## 6. Evaluation

An authorization decision resolves to `(allowed, reason)`. `reason` is part of
the answer, not a debug afterthought, because D1 §10.2 requires the platform
to explain itself honestly to the operator.

- A denial names the missing capability and, where the caller can see it, the
  role that was consulted.
- A denial is recorded in the audit trail with outcome `denied` (D4 §12), so
  "who tried and was refused" is answerable.
- The TUI and the CLI surface the same reason. A capability the caller lacks is
  shown as denied, not as absent — the operator learns the operation exists and
  that they cannot perform it, which is more useful than a menu that silently
  omits it.

---

## 7. Tests this model must pass

Authorization is only as good as its negative tests. The following are
required, and are stated here as acceptance criteria for D5 rather than as
implementation notes.

### 7.1 Deny-by-default

- A user with no roles has **no** effective capability, and every protected
  operation is refused.
- A role with an empty capability set grants nothing.
- A capability that exists in the table but is granted to no role is refused
  for every user, including full administrators.

### 7.2 No implicit future capabilities (the `admin` test)

- Snapshot the `admin` role's capability set.
- Introduce a **new** capability (a fixture module registering one).
- Assert the administrator's effective set is **byte-identical** and that
  performing the new operation is refused.
- Assert it becomes permitted only after an explicit `role.grant`.

This is the test that makes §3 and §5 true rather than aspirational.

### 7.3 Cross-tenant negative tests

For **every** tenant-scoped read and every tenant-scoped write in the API
surface, a test creates tenant A and tenant B, populates a known object in
each, and asserts:

| Case | Expected |
|---|---|
| A reads A's object | allowed, returns A's data |
| A reads B's object **by id** | **refused**; not a 404-with-A's-data, not a silent empty |
| A writes B's object **by id** | **refused**, and B's object is **unchanged** |
| A lists objects | returns **only** A's |
| A uses a binding/provider-instance id owned by B | **refused** |
| A switches session context to B | permitted only if granted a role in B; then scoped to B and re-authorized |

The "by id" cases are the ones that matter: an id-addressed object must not
be reachable across tenants by construction, and a listing must not leak by
omission. Both are asserted explicitly rather than inferred from the list test.

### 7.4 Interface parity

Every capability-gated operation available in the TUI is available in the CLI
with the same authorization outcome, and the reverse. There is no privileged
or configuration operation that exists only in the TUI (D1 §2.1). A test walks
the operation registry and asserts the two interfaces expose the same set.

### 7.5 Module-absence parity

With a module absent, its capabilities do not exist, cannot be granted, and
cannot be exercised; with it present and granted, they can. Asserted for both
directions so that module removal is provably clean (D2 §8).

---

## 8. What this model does not claim

- It does not claim the TUI hides what a user cannot do. It shows it, denied,
  with a reason.
- It does not claim `admin` is powerful. It is powerful only by an enumerated
  grant, and it does not grow on its own.
- It does not model a "break glass" bypass. If an emergency path is ever
  wanted, it is a separate, separately-audited, time-bounded capability — never
  an implicit one, and not part of this design.
- It does not treat a module's presence as authority. Modules act as the
  calling user through the core's authorization service (D2 §5, D3 §4).

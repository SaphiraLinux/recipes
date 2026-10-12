# D2 — Module ABI

Status: **design, not implementation.** Companion to D1. Read D1 first —
this document assumes the core/service split and the interface hierarchy
established there.

---

## 1. Why a module system at all

`saphira-router` drives several independent daemons. If provider support were
compiled into the core, every new technology would mean editing the
authentication system, the database core, the CLI dispatcher, the TUI router
and the transaction engine. That is the failure mode this ABI exists to
prevent.

The requirement, restated as a test:

> **Design test.** Adding a future `saphira-router-udpdist` module must not
> require editing the authentication system, the database core, the CLI
> dispatcher, the TUI router or the transaction engine. It should register its
> capabilities and interfaces and appear naturally in the platform.

§9 turns this from a slogan into something CI can execute.

---

## 2. Shape

Opaque structs, explicit interfaces, versioned function tables. Idiomatic C —
**not** an imitation of C++ classes. The useful properties are encapsulation,
polymorphic providers, lifecycle and clean boundaries; the syntax stays C.

```c
/* Opaque to every module. Modules never see a core struct. */
typedef struct sr_module      sr_module;
typedef struct sr_module_ctx  sr_module_ctx;   /* per-load instance */

/* Opaque object model, owned by core. */
typedef struct sr_value       sr_value;        /* description/transport value */
typedef struct sr_ctx         sr_ctx;          /* core services + tenant scope */
```

Every core type a module touches is **opaque and owned by core**. A module
cannot dereference core state, because it has no declaration for it.

---

## 3. The module descriptor

A module exports exactly one symbol, a descriptor:

```c
#define SR_MODULE_ABI_VERSION 1

typedef struct sr_module_descriptor {
    uint32_t      abi_version;        /* must equal SR_MODULE_ABI_VERSION      */
    const char   *name;               /* "haproxy", "ovs", "gredist", ...     */
    const char   *version;            /* module's own version                  */
    const char   *summary;            /* one line, for the TUI                 */

    /* Capability flags: what this module actually provides. Declared, not
     * assumed. A consumer must check these before calling an operation.     */
    uint64_t      provides;           /* SR_PROVIDES_* bitmask                 */
    uint64_t      requires;           /* SR_REQUIRES_* bitmask, e.g. ldirectord*/

    /* Dependencies on other modules, by name. Core resolves and orders.      */
    const char * const *dependencies; /* NULL-terminated, may be NULL          */

    /* The operation table.                                                 */
    const sr_module_ops *ops;
} sr_module_descriptor;
```

Exported as `sr_module_descriptor_get()` (or, at ABI 1, a bare
`sr_module_descriptor` symbol — the exact spelling is an implementation
detail; the *contract* is: one descriptor, versioned).

### 3.1 Capability flags

Flags are declared, never assumed. Consequences:

- A consumer **must** check `provides` before calling an operation.
- A module that does not provide an operation **must** not advertise it.
- The TUI derives its sections and actions from capabilities (D1 §6.4), so an
  absent capability is a *missing section*, not a broken menu.

This is the mechanism by which "install `saphira-router-haproxy` makes HAProxy
functionality appear; remove it and it disappears cleanly" (§4, §8) actually
works: the TUI is driven by the registry, not by a hard-coded provider list.

---

## 4. Operations

Not every module implements every operation. Capability flags say which.

| Operation | Purpose | Provider-neutral intent |
|---|---|---|
| `init` | bind to core services, register | lifecycle |
| `shutdown` | release | lifecycle |
| `describe` | **declarative object/field/action schema** | how the TUI renders this module |
| `validate` | check a candidate without applying | pre-flight |
| `discover` | find existing state on a host | inventory / adoption |
| `observe` | read current runtime state | observed state |
| `render` | objects → provider config | configuration generation |
| `stage` | write candidate to a staging area, not live | deployment |
| `apply` | atomically activate staged config | deployment |
| `verify` | confirm the change took effect | post-activation |
| `rollback` | restore a retained prior state | deployment |

`stage` / `apply` / `verify` / `rollback` are the D1 §10 / D8 transaction
pipeline hooks. A module that cannot verify (because its component exposes no
verification surface) declares that it does not provide `verify` and the core
degrades honestly rather than pretending a check happened.

### 4.1 `describe` — the declarative description layer

This is the operation that makes the TUI-primary, no-browser design work, and
it is **data, not drawing**.

A module may **not** draw terminal UI. It declares:

- the **object types** it contributes (e.g. for HAProxy: `frontend`, `backend`,
  `acl`, `rule`, `rewrite`, `map`, `stick_table`);
- the **fields** of each type (name, type, required, default, validation
  hint, sensitivity flag);
- the **actions** available on each object (create, edit, delete, validate,
  and provider-specific verbs);
- the **rendering kind** for a field (text, int, bool, enum, address,
  address-family pair, secret-reference, weight) so a generic TUI can draw a
  form without the module knowing about ncurses.

The TUI owns rendering and navigation. The module owns meaning. That division
is what keeps the interface consistent, and it is exactly what a future web
client would consume instead of a bespoke UI.

**`describe` is the seam that keeps deferred web cheap.** Nothing in the core
or the ABI may *require* a web client; it simply means a future client reads
the same description the TUI reads.

### 4.2 What a module is explicitly forbidden to do

- Draw terminal UI, or emit escape sequences for the screen.
- Hold a database handle, or open the SQLite file itself.
- Authenticate, authorize, or read a secret directly.
- Write an audit record directly.
- Mutate desired or observed state directly.
- Assume a capability the host lacks (the host inventory is core's business).

All state change and authority flow through the core services it is given
(§5). This is a **contract**, and the in-process trust caveat is stated
plainly in D3 §2: an in-process `.so` is trusted first-party code, not a
sandbox.

---

## 5. Core services handed to a module

At `init`, core provides a `sr_ctx` carrying function tables for the platform
services the core owns (D1 §5). A module uses these; it does not reimplement
or bypass them.

```c
/* Values cross the boundary as data, not as core pointers. */
typedef struct sr_value {
    sr_value_type type;     /* string, int, bool, list, map, secretref, ... */
    const char   *key;      /* for maps                                    */
    const char   *sval;     /* string / serialized form                    */
    int64_t       ival;
    int           bval;
    size_t        list_len;
} sr_value;
```

The services a `sr_ctx` exposes (signatures are design-level; exact C types
are an implementation detail):

| Service | Purpose |
|---|---|
| `authorize(capability, scope)` | capability check, per (actor, tenant) |
| `state_get` / `state_put` | desired-state read/write, core-mediated |
| `observe_put` | record observed state, with provenance |
| `audit(op, object, before, after)` | write the audit trail |
| `secret_ref(kind, name)` | a **reference** to a secret, never its value |
| `register_description(...)` | contribute `describe` output to the TUI |
| `host_capability(host, cap)` | ask whether a host has a capability |
| `log(level, fmt, ...)` | structured logging into the event system |
| `transaction_scope()` | the current transaction, for staging/rollback |

Two consequences worth stating:

1. **No DB handles.** A module physically cannot open the database through the
   supported surface, because it is never given one.
2. **Secrets by reference.** `secret_ref` returns a handle for *use*, never a
   plaintext value into a module that might log it (D3).

---

## 6. Versioning and compatibility

- **The ABI is versioned from day one.** `abi_version` is a hard gate.
- A module whose `abi_version` the core does not implement is **refused with
  a clear diagnostic** naming module, its version and the versions the core
  supports. **Never loaded optimistically.**
- The core and each module carry independent versions; a module upgrade does
  not require a core upgrade, provided the ABI major matches.
- **The core must remain usable with any module absent**, and with *all*
  modules absent. A missing module is a missing capability, not a fatal error.

---

## 7. Discovery and packaging

- **Runtime discovery, not a compiled-in list.** The core scans a module
  directory for loadable objects, reads each descriptor, and builds the
  capability registry from what is actually present.
- Loading is by **absolute path**; Saphira is non-merged-`/usr` with a musl
  search path compiled in, so module location is explicit, never a
  `ld.so.conf`/`ldconfig` mechanism (D1 §9).
- Each module is its own package (`saphira-router-haproxy`, …), installed or
  removed independently. Removal retires that capability cleanly without
  breaking the core or the rest of the TUI.
- A module is **trusted first-party code sharing the core process** (D3 §2).
  The ABI is deliberately narrow and data-oriented so a future helper process
  can back the same interface without changing the domain or API contract —
  but no serialization/process overhead is introduced now (D1, D3 §8).

---

## 8. Registration → appearance → disappearance

The lifecycle an operator sees, and the one the acceptance criterion depends on:

1. `saphira-router-haproxy` installed → module discovered at startup → its
   `describe` output registered → the TUI gains HAProxy sections and actions,
   derived from the registry, **without the TUI being modified**.
2. HAProxy objects become renderable/validatable for capable hosts.
3. `saphira-router-haproxy` removed → capability drops out of the registry →
   those TUI sections disappear cleanly; the core and every other section keep
   working. HAProxy-owned objects remain in the database as inert, unrenderable
   records (D4) rather than being silently destroyed.

Step 3's "rather than silently destroyed" is the same rule that governs the
advanced-directive escape hatch (D4): data the core cannot currently render is
**retained**, never dropped on the floor.

---

## 9. The design test, made executable

The requirement from §1 is verified in CI as a fixture, not by inspection:

A **test-only fixture module** (a minimal `mod_udpdist`) is added to the tree
and the suite asserts:

- it builds and loads against the current ABI;
- it registers capabilities and a `describe` schema;
- the TUI registry gains a `udpdist` section with no TUI source change;
- after (snapshot) → before (compare), these five core files are
  **byte-identical**:
  - the authentication service
  - the database core
  - the CLI dispatcher
  - the TUI router
  - the transaction engine

If adding the module requires editing any of those five, **the design has
failed** and the test fails. The five files are pinned by content hash in the
suite for exactly this purpose.

---

## 10. A worked descriptor (illustrative, not code)

To make the contract concrete, a sketch of a HAProxy module descriptor —
fields and flags only, no implementation:

```
abi_version  = 1
name         = "haproxy"
version      = "0.1.0"
provides     = RENDER | VALIDATE | STAGE | APPLY | DESCRIBE | OBSERVE
requires     = (none)
dependencies = (none)
ops.describe -> contributes object types: frontend, backend, server, acl,
                rule, rewrite, map, stick_table
ops.render   -> desired HAProxy config (text)
ops.validate -> haproxy -c -f  (read-only; the component provides this)
ops.observe  -> from the HAProxy runtime socket, if present
```

`observe` is listed but its *availability* is conditional at runtime on the
component exposing a runtime socket — which, per D1 Appendix A.2, the shipped
Saphira HAProxy does not. In that case the module reports the capability as
unavailable and the TUI shows the operator the honest gap ("HAProxy observed
state unavailable: runtime socket not configured") rather than inventing
health (D1 §10.2). This is the behaviour the design is supposed to produce,
and it is why `describe` and `provides` exist separately from the runtime
truth of a particular node.

---

## 11. ABI change policy

- Additive changes (new trailing struct fields, new optional ops with new
  `provides` flags) may bump the ABI **minor**; old modules keep working.
- A change that alters an existing operation's meaning, a struct layout, or
  the core-service contract bumps the ABI **major**; incompatible modules are
  refused with a diagnostic, not coerced.
- The core ships the current ABI version and the range it accepts; a module
  declares one. Mismatch is a startup-time, per-module, clearly-reported
  condition — never a partial load.

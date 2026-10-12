# D4 — Database and domain schema

Status: **design, not implementation.** Companion to D1–D3. This document
defines the **domain model** and its persistence, on **SQLite** as the
rollback and history store. No SQL below is written against code that exists
yet; it is the schema the code will implement.

---

## 1. Storage decision and discipline

- **SQLite** is the single persistent store: desired state, observed state,
  history, audit, transactions, and the domain model. It is chosen because it
  is packaged and musl-safe, gives a single-file rollback/history store, and
  matches how `saphira-build` already persists its queue — while adding the
  concurrency discipline that store lacks.
- **One authority for writes: the core.** Neither the TUI nor the CLI ever
  writes SQLite. Neither does a drone, a module, or an observer. Every
  mutation — from any source, human or automated — is submitted to the core
  over IPC and applied by the core-owned state service (D2 §5):

  ```
  TUI ─┐
  CLI ─┼── IPC ──> core ──> SQLite
       │
  observer/module callbacks ──> core services ──> SQLite
  ```

  This is a **security boundary, not a style preference** (D3). If a client
  process could open the database and write it, then RBAC, the audit trail,
  the transaction engine, and the desired/observed separation would all be
  bypassable by anyone who could `sqlite3` the file. The single-write-authority
  rule is what makes those invariants hold; the file mode is a backstop, not
  the mechanism.

- **Concurrency discipline (WAL):** the database runs in **WAL** journal mode
  with a nonzero `busy_timeout` (the working pattern used by the Saphira
  memory backend). The `saphira-build` queue runs in `delete` mode with
  `busy_timeout=0`; that is **not** copied here. The reason is **concurrency
  within the control plane**, not outside it: the core is itself concurrent —
  API request handling, background observers, transaction processing, and
  possibly worker threads all share the one connection pool. WAL plus a real
  busy timeout is what lets those internal readers and writers coexist.

  **WAL is not permission for external clients to write the database.** It
  buys internal concurrency for the core; it does not widen the write surface.
- **Migrations:** versioned by `PRAGMA user_version`, applied in order at
  startup by the core, each with a recorded checksum. There is no precedent
  for this in the Saphira tree, so it is introduced deliberately here.

### 1.1 Naming and typing conventions

- `snake_case` tables and columns; `id` is a stable opaque identifier.
- Timestamps are UTC, ISO-8601 text (readable in the TUI and in ad-hoc
  `sqlite3` inspection, which matters for a platform people debug by hand).
- IPv4 and IPv6 are stored in **separate** columns, never one string, so
  IPv6-first and IPv4-complete both query cleanly (D1 §9, IPv6-first house
  policy).
- Sensitive fields are marked; secrets are never stored here (D3 §5) — only
  references are.
- Every tenant-scoped table carries `tenant_id` and is filtered by it on
  every access (D3 §4).

---

## 2. Ownership: core vs module

- **Core-owned** (D1 §5): identity/tenancy, the common service model
  (`virtual_service`, `real_server`, `health_check`, …), desired/observed
  state, transactions, audit, secrets references, module registry.
- **Module-owned namespace** (D2): a module may own its provider-specific
  schema and migrations, but only under its namespace (e.g. tables prefixed
  `haproxy_`, `gredist_`, `ovs_`, `dns_`, `libvirt_`, `ipvs_`). A module
  migration is applied by the core on the module's behalf and recorded in the
  same migration ledger.
- **Rule:** a module may not write core-owned tables, and the core does not
  interpret module-owned tables. The common service model does not change
  because a module adds provider-specific objects (D1 §7.4).

---

## 3. Migration ledger

```sql
CREATE TABLE schema_migration (
  version     INTEGER PRIMARY KEY,      -- == PRAGMA user_version after apply
  name        TEXT    NOT NULL,
  checksum    TEXT    NOT NULL,         -- guards against edited migrations
  applied_at  TEXT    NOT NULL
);
```

`PRAGMA user_version` holds the highest applied `version`. A checksum mismatch
on an already-applied migration is a startup error (the database is not
silently trusted).

---

## 4. Identity, tenancy and access (core)

```sql
CREATE TABLE tenant (
  id          TEXT PRIMARY KEY,
  slug        TEXT NOT NULL UNIQUE,
  name        TEXT NOT NULL,
  status      TEXT NOT NULL DEFAULT 'active',   -- active|suspended
  created_at  TEXT NOT NULL,
  updated_at  TEXT NOT NULL
);

CREATE TABLE app_user (
  id                 TEXT PRIMARY KEY,
  username           TEXT NOT NULL,
  email              TEXT,
  password_algo      TEXT NOT NULL DEFAULT 'argon2id',
  password_hash      TEXT NOT NULL,             -- Argon2id encoded; no plaintext
  failed_attempts    INTEGER NOT NULL DEFAULT 0,
  locked_until       TEXT,
  last_login_at      TEXT,
  status             TEXT NOT NULL DEFAULT 'active',
  created_at         TEXT NOT NULL,
  updated_at         TEXT NOT NULL,
  UNIQUE (username)
);

-- Roles are per-tenant, or system-wide when tenant_id IS NULL.
CREATE TABLE role (
  id          TEXT PRIMARY KEY,
  tenant_id   TEXT REFERENCES tenant(id),       -- NULL = system role
  name        TEXT NOT NULL,
  description TEXT,
  is_system   INTEGER NOT NULL DEFAULT 0,
  UNIQUE (tenant_id, name)
);

-- Explicit capabilities; admin is a curated set, not a wildcard (D3 §4).
CREATE TABLE capability (
  code        TEXT PRIMARY KEY,                 -- e.g. 'virtual_service.write'
  description TEXT
);

CREATE TABLE role_capability (
  role_id         TEXT NOT NULL REFERENCES role(id),
  capability_code TEXT NOT NULL REFERENCES capability(code),
  PRIMARY KEY (role_id, capability_code)
);

-- A user's role bindings, scoped to a tenant.
CREATE TABLE user_role (
  user_id    TEXT NOT NULL REFERENCES app_user(id),
  role_id    TEXT NOT NULL REFERENCES role(id),
  tenant_id  TEXT NOT NULL REFERENCES tenant(id),
  PRIMARY KEY (user_id, role_id, tenant_id)
);

-- Sessions are scoped to (user, tenant); token is stored hashed (D3 §3).
CREATE TABLE session (
  id           TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL REFERENCES app_user(id),
  tenant_id    TEXT NOT NULL REFERENCES tenant(id),   -- active context
  token_hash   TEXT NOT NULL UNIQUE,
  source_addr  TEXT,
  created_at   TEXT NOT NULL,
  expires_at   TEXT NOT NULL,
  last_seen_at TEXT,
  revoked_at   TEXT
);
```

A session binds one user to one tenant context; switching context is explicit
and re-authorized (D3 §3).

---

## 5. Managed nodes (core)

```sql
CREATE TABLE host (
  id                TEXT PRIMARY KEY,
  tenant_id         TEXT NOT NULL REFERENCES tenant(id),
  hostname          TEXT NOT NULL,
  address_v4        TEXT,
  address_v6        TEXT,
  os_name           TEXT,
  os_version        TEXT,
  arch              TEXT,
  init_system       TEXT,                        -- openrc|systemd
  drone_version     TEXT,
  identity_fingerprint TEXT,                     -- pinned node key
  status            TEXT NOT NULL DEFAULT 'unknown',  -- unknown|online|offline
  enrolled_at       TEXT,
  last_seen_at      TEXT,
  UNIQUE (tenant_id, hostname)
);

-- Capability inventory; drives refusal to deploy (D6).
CREATE TABLE host_capability (
  host_id       TEXT NOT NULL REFERENCES host(id),
  capability    TEXT NOT NULL,                   -- ipvs|haproxy|ovs|gredist|...
  version       TEXT,
  detail        TEXT,                            -- JSON blob
  discovered_at TEXT NOT NULL,
  PRIMARY KEY (host_id, capability)
);

CREATE TABLE host_package (
  host_id       TEXT NOT NULL REFERENCES host(id),
  name          TEXT NOT NULL,
  version       TEXT,
  discovered_at TEXT NOT NULL,
  PRIMARY KEY (host_id, name)
);

CREATE TABLE cluster (
  id          TEXT PRIMARY KEY,
  tenant_id   TEXT NOT NULL REFERENCES tenant(id),
  name        TEXT NOT NULL,
  description TEXT
);

CREATE TABLE cluster_host (
  cluster_id TEXT NOT NULL REFERENCES cluster(id),
  host_id    TEXT NOT NULL REFERENCES host(id),
  role       TEXT,
  PRIMARY KEY (cluster_id, host_id)
);
```

Node self-reported capability is untrusted input (D3 §7); the core decides what
a host may host from its own policy, using this table as evidence, not as
authorization.

---

## 6. Virtual networking (core)

```sql
CREATE TABLE interface (
  id           TEXT PRIMARY KEY,
  tenant_id    TEXT NOT NULL REFERENCES tenant(id),
  host_id      TEXT REFERENCES host(id),
  name         TEXT NOT NULL,
  kind         TEXT NOT NULL,     -- physical|bond|vlan|port|tunnel|patch|vm
  parent_id    TEXT REFERENCES interface(id),
  mac          TEXT,
  mtu          INTEGER,
  admin_state  TEXT NOT NULL DEFAULT 'up',   -- up|down
  oper_state   TEXT,                        -- observed
  -- No provider column here. How this interface is realised (OVS, plain
  -- Linux networking, a future provider) is a deployment binding, held in
  -- resource_binding (§6.1) so core objects stay provider-agnostic.
  UNIQUE (host_id, name)
);

CREATE TABLE bridge (
  id          TEXT PRIMARY KEY,
  tenant_id   TEXT NOT NULL REFERENCES tenant(id),
  host_id     TEXT REFERENCES host(id),
  name        TEXT NOT NULL,
  -- Realised by which provider is a binding, not an attribute (§6.1).
  UNIQUE (host_id, name)
);

CREATE TABLE vlan (
  id          TEXT PRIMARY KEY,
  tenant_id   TEXT NOT NULL REFERENCES tenant(id),
  bridge_id   TEXT NOT NULL REFERENCES bridge(id),
  vlan_id     INTEGER NOT NULL,               -- 0..4094
  name        TEXT,
  description TEXT,
  UNIQUE (bridge_id, vlan_id)
);

CREATE TABLE network (
  id          TEXT PRIMARY KEY,
  tenant_id   TEXT NOT NULL REFERENCES tenant(id),
  name        TEXT NOT NULL,
  cidr_v4     TEXT,
  cidr_v6     TEXT,                           -- IPv6-first: both optional
  bridge_id   TEXT REFERENCES bridge(id),
  mtu         INTEGER,
  state       TEXT NOT NULL DEFAULT 'active'
);

CREATE TABLE pppoe_session (
  id              TEXT PRIMARY KEY,
  tenant_id       TEXT NOT NULL REFERENCES tenant(id),
  host_id         TEXT NOT NULL REFERENCES host(id),
  interface_id    TEXT NOT NULL REFERENCES interface(id),
  name            TEXT NOT NULL,
  service         TEXT,
  username_ref    TEXT,                       -- secret REFERENCE, never value
  secret_ref      TEXT,                       -- secret REFERENCE, never value
  vlan_id         INTEGER,
  mtu             INTEGER,
  mru             INTEGER,
  ipv4_mode       TEXT,
  ipv6_mode       TEXT,
  route_policy    TEXT,
  state           TEXT NOT NULL DEFAULT 'inactive',
  UNIQUE (host_id, name)
);
```

PPPoE credentials are **references**; plaintext never lives here and never
crosses an ordinary API response (D3 §5, D1 A.5). PPPoE is modelled as a
networking primitive, not a command textbox (D1 A.5).

### 6.1 Deployment binding: provider instances and resource bindings

Core **must** know that a logical `Interface` or `Bridge` is *realised* by
something — an OVS datapath, the plain Linux network stack, a libvirt
network, and later others. That is **deployment binding**, and it is
legitimate for core to know it: without it, core could not tell an operator
whether a bridge exists or what a drift actually means.

What core must *not* do is encode one provider's assumptions into its own
tables. So realisation is held in a **generic binding model** rather than a
free-form `provider_ref` column. One mechanism serves OVS today and every
future provider, and adding a provider adds rows — never a column or a schema
change.

```sql
-- A logical provider instance: a named deployment target owned by a module.
-- e.g. ('ovs', 'datapath on nodea'), ('linux-net', 'kernel stack on nodea'),
--      ('libvirt', 'default network on nodea').
CREATE TABLE provider_instance (
  id            TEXT PRIMARY KEY,
  tenant_id     TEXT NOT NULL REFERENCES tenant(id),
  name          TEXT NOT NULL,        -- logical label, operator-facing
  module_name   TEXT NOT NULL,        -- owning module ('ovs', 'libvirt', ...)
  scope_host_id TEXT REFERENCES host(id),
  scope         TEXT,                 -- provider's own scope, opaque
  capabilities  TEXT,                 -- JSON, as advertised by the module
  status        TEXT NOT NULL DEFAULT 'active',
  created_at    TEXT NOT NULL,
  UNIQUE (tenant_id, name)
);

-- Binds a core object to a native object inside a provider instance.
-- provider_instance_id and native_id are deliberately generic: the core
-- never interprets either.
CREATE TABLE resource_binding (
  id                  TEXT PRIMARY KEY,
  tenant_id           TEXT NOT NULL REFERENCES tenant(id),
  provider_instance_id TEXT NOT NULL REFERENCES provider_instance(id),
  resource_type       TEXT NOT NULL,   -- core type: 'interface'|'bridge'|'network'|'virtual_network'|...
  resource_id         TEXT NOT NULL,   -- core object id
  native_id           TEXT,            -- provider's own handle, opaque to core
  native_type         TEXT,            -- provider-side type/kind, informational
  attributes          TEXT,            -- JSON, provider-specific, non-authoritative
  bound_at            TEXT NOT NULL,
  UNIQUE (resource_type, resource_id)
);
CREATE INDEX resource_binding_instance
  ON resource_binding (provider_instance_id);
```

Rules:

- A core object may have **zero or one** binding per provider instance. Zero
  bindings means "not yet realised" — a legitimate, reportable state.
- `native_id` and `attributes` are **opaque to core**. Core records the
  binding and shows it; only the owning module interprets it. If the owning
  module is removed, bindings become inert and are retained, not destroyed
  (D1 §6.2, D2 §8).
- When a provider is later replaced (say a bridge moves from the plain Linux
  stack to OVS), this is a **change of binding rows**, not a migration of
  core object identity. The `bridge` stays the same object; what realises it
  changes. That is the point of separating the two.

---

## 7. The common service model (core) — and the VIP projection

This is the model that keeps the platform one platform (D1 §7.3):
`VirtualService` / `RealServer` / `HealthCheck` are core objects; modules are
renderers of them.

```sql
CREATE TABLE load_balancer (
  id           TEXT PRIMARY KEY,
  tenant_id    TEXT NOT NULL REFERENCES tenant(id),
  name         TEXT NOT NULL,
  -- Which renderer implements this LB. Policy, not identity (D1 §7.3).
  renderer_module TEXT NOT NULL,              -- e.g. 'ldirectord' | 'haproxy'
  renderer_config  TEXT,                      -- module-owned knobs, JSON
  enabled      INTEGER NOT NULL DEFAULT 1,
  UNIQUE (tenant_id, name)
);

CREATE TABLE virtual_service (
  id            TEXT PRIMARY KEY,
  tenant_id     TEXT NOT NULL REFERENCES tenant(id),
  lb_id         TEXT NOT NULL REFERENCES load_balancer(id),
  name          TEXT NOT NULL,
  protocol      TEXT NOT NULL,                -- tcp|udp|sctp
  vip_v4        TEXT,
  vip_v6        TEXT,                         -- IPv6-first
  vport         INTEGER NOT NULL,
  netmask_v4    TEXT,
  netmask_v6    TEXT,
  scheduler     TEXT,                         -- module/renderer-relevant
  persistence   TEXT,
  fallback_server   TEXT,                     -- e.g. for LVS
  gate          TEXT,
  desired_enabled INTEGER NOT NULL DEFAULT 1, -- desired, not observed
  UNIQUE (tenant_id, name)
);

CREATE TABLE real_server (
  id                TEXT PRIMARY KEY,
  tenant_id         TEXT NOT NULL REFERENCES tenant(id),
  virtual_service_id TEXT NOT NULL REFERENCES virtual_service(id),
  name              TEXT NOT NULL,
  address_v4        TEXT,
  address_v6        TEXT,
  rport             INTEGER,
  weight            INTEGER NOT NULL DEFAULT 1,
  priority          INTEGER NOT NULL DEFAULT 0,
  -- admin intent, distinct from observed health (D7)
  admin_state       TEXT NOT NULL DEFAULT 'enabled', -- enabled|disabled|drain|maint
  health_check_id   TEXT REFERENCES health_check(id),
  UNIQUE (virtual_service_id, name)
);

CREATE TABLE health_check (
  id          TEXT PRIMARY KEY,
  tenant_id   TEXT NOT NULL REFERENCES tenant(id),
  name        TEXT NOT NULL,
  type        TEXT NOT NULL,     -- external|lb-saphira-<name>|native
  command_ref TEXT,              -- for external checks
  interval_s  INTEGER,
  timeout_s   INTEGER,
  rise        INTEGER,
  fall        INTEGER,
  params      TEXT,              -- JSON
  enabled     INTEGER NOT NULL DEFAULT 1
);
```

### 7.1 The VIP abstraction is a projection, not a second model

The everyday admin view —

```
VIP: address, port/protocol, algorithm, healthcheck, RIPs
```

— is a **read projection** over `virtual_service` + `real_server` +
`health_check` for a chosen `renderer_module`. It is not a separate table and
not a competing model (D1 §7.2). A simple service is expressible without
touching any provider-native object.

---

## 8. Provider-native objects (module-owned namespaces)

Kept available where the common model is insufficient (D1 §7.4), namespaced so
they never contaminate other modules. Shown here for the HAProxy family as the
worked example; `gredist_`, `ovs_`, `dns_`, `libvirt_`, `ipvs_` follow the same
pattern under their owning module.

```sql
-- HAProxy (module: haproxy)
CREATE TABLE haproxy_frontend (
  id          TEXT PRIMARY KEY,
  tenant_id   TEXT NOT NULL REFERENCES tenant(id),
  name        TEXT NOT NULL,
  mode        TEXT NOT NULL,          -- tcp|http
  bind_json   TEXT NOT NULL,          -- listen address/port, v4+v6
  mode_ssl    INTEGER NOT NULL DEFAULT 0,
  default_backend TEXT,
  advanced_directives TEXT            -- raw/advanced escape hatch
);

CREATE TABLE haproxy_backend (
  id          TEXT PRIMARY KEY,
  tenant_id   TEXT NOT NULL REFERENCES tenant(id),
  name        TEXT NOT NULL,
  mode        TEXT NOT NULL,
  balance     TEXT,                   -- roundrobin|leastconn|source|...
  advanced_directives TEXT
);

CREATE TABLE haproxy_server (
  id          TEXT PRIMARY KEY,
  backend_id  TEXT NOT NULL REFERENCES haproxy_backend(id),
  address_v4  TEXT,
  address_v6  TEXT,
  port        INTEGER NOT NULL,
  weight      INTEGER,
  admin_state TEXT NOT NULL DEFAULT 'ready',   -- ready|drain|maint
  advanced_directives TEXT
);

CREATE TABLE haproxy_acl (
  id          TEXT PRIMARY KEY,
  tenant_id   TEXT NOT NULL REFERENCES tenant(id),
  name        TEXT NOT NULL,
  definition  TEXT NOT NULL,          -- e.g. hdr(host) -i example.org
  advanced_directives TEXT
);

CREATE TABLE haproxy_rule (
  id          TEXT PRIMARY KEY,
  tenant_id   TEXT NOT NULL REFERENCES tenant(id),
  -- bound to a frontend or backend; kind selects request/response handling
  scope       TEXT NOT NULL,          -- frontend|backend
  scope_id    TEXT NOT NULL,
  kind        TEXT NOT NULL,          -- request|response|redirect|use_backend
  match_acl  TEXT,
  action      TEXT,
  advanced_directives TEXT
);

CREATE TABLE haproxy_rewrite (
  id          TEXT PRIMARY KEY,
  tenant_id   TEXT NOT NULL REFERENCES tenant(id),
  name        TEXT NOT NULL,
  condition   TEXT,
  rewrite     TEXT,
  advanced_directives TEXT
);
```

The `advanced_directives` columns are the **raw/advanced escape hatch**: text
for directives the structured model does not yet understand. They are
first-class and preserved verbatim so a directive is never silently destroyed
on the next save (D1 §7.4, D8).

---

## 9. DNS and virtualization (module-owned; represented now, not blocking)

Present now so the schema does not paint us into a corner; they do not block
the first working load-balancer control plane (D1 A.6, A.7).

```sql
-- DNS (module: bind9)
CREATE TABLE dns_zone (
  id          TEXT PRIMARY KEY,
  tenant_id   TEXT NOT NULL REFERENCES tenant(id),
  name        TEXT NOT NULL,
  zone_type   TEXT NOT NULL,
  status      TEXT NOT NULL DEFAULT 'active',
  serial      INTEGER,
  UNIQUE (tenant_id, name)
);

-- Revision/audit history for a zone, with validation-before-reload (D1 A.6).
CREATE TABLE dns_zone_revision (
  id          TEXT PRIMARY KEY,
  zone_id     TEXT NOT NULL REFERENCES dns_zone(id),
  revision    INTEGER NOT NULL,
  rdata       TEXT NOT NULL,          -- the generated zone content
  validated   INTEGER NOT NULL DEFAULT 0,
  validated_at TEXT,
  created_at  TEXT NOT NULL,
  UNIQUE (zone_id, revision)
);

CREATE TABLE dns_record (
  id          TEXT PRIMARY KEY,
  zone_id     TEXT NOT NULL REFERENCES dns_zone(id),
  name        TEXT NOT NULL,
  record_type TEXT NOT NULL,          -- A|AAAA|CNAME|MX|TXT|SRV|...
  ttl         INTEGER,
  value_v4    TEXT,                   -- for A
  value_v6    TEXT,                   -- for AAAA
  value_text  TEXT,                   -- for the general case
  active      INTEGER NOT NULL DEFAULT 1
);

-- Virtualization (module: libvirt)
CREATE TABLE virtual_machine (
  id          TEXT PRIMARY KEY,
  tenant_id   TEXT NOT NULL REFERENCES tenant(id),
  host_id     TEXT NOT NULL REFERENCES host(id),
  name        TEXT NOT NULL,
  uuid        TEXT,
  vcpus       INTEGER,
  memory_mb   INTEGER,
  state       TEXT,                   -- observed
  console_ref TEXT,
  UNIQUE (host_id, name)
);

CREATE TABLE vm_disk (
  id          TEXT PRIMARY KEY,
  vm_id       TEXT NOT NULL REFERENCES virtual_machine(id),
  name        TEXT NOT NULL,
  backing     TEXT NOT NULL,
  size_bytes  INTEGER,
  format      TEXT
);

CREATE TABLE vm_interface (
  id          TEXT PRIMARY KEY,
  vm_id       TEXT NOT NULL REFERENCES virtual_machine(id),
  mac         TEXT,
  network_id  TEXT REFERENCES network(id),   -- attach to Saphira networking
  bridge_id   TEXT REFERENCES bridge(id),
  model       TEXT
);

CREATE TABLE storage_pool (
  id          TEXT PRIMARY KEY,
  tenant_id   TEXT NOT NULL REFERENCES tenant(id),
  host_id     TEXT NOT NULL REFERENCES host(id),
  name        TEXT NOT NULL,
  pool_type   TEXT,
  backing_path TEXT,
  capacity_bytes INTEGER,
  allocated_bytes INTEGER
);

CREATE TABLE virtual_network (
  id          TEXT PRIMARY KEY,
  tenant_id   TEXT NOT NULL REFERENCES tenant(id),
  name        TEXT NOT NULL,
  bridge_id   TEXT REFERENCES bridge(id),
  is_isolated INTEGER NOT NULL DEFAULT 0
);
```

DNS and VM records are represented but are **not** M1 acceptance blockers. VM
operations are a distinct high-privilege capability class (D3 §8) because
`virtqemud` ships with no access control.

---

## 10. Desired state vs observed state (core)

The separation the platform is judged on (D1 §4 row 12, D7).

```sql
-- Desired: what the operator asked for. Never overwritten by runtime health.
CREATE TABLE desired_state (
  object_type  TEXT NOT NULL,
  object_id    TEXT NOT NULL,
  tenant_id    TEXT NOT NULL REFERENCES tenant(id),
  desired_json TEXT NOT NULL,          -- the intended spec
  spec_revision INTEGER NOT NULL,
  updated_by   TEXT REFERENCES app_user(id),
  updated_at   TEXT NOT NULL,
  PRIMARY KEY (object_type, object_id)
);

-- Observed: what the platform last saw. Health lives here, never in desired.
CREATE TABLE observed_state (
  object_type  TEXT NOT NULL,
  object_id    TEXT NOT NULL,
  tenant_id    TEXT NOT NULL REFERENCES tenant(id),
  observed_json TEXT NOT NULL,
  health       TEXT NOT NULL,          -- healthy|unhealthy|down|draining|unknown
  source       TEXT NOT NULL,          -- e.g. 'drone','haproxy-runtime'
  observed_at  TEXT NOT NULL,
  detail       TEXT,
  PRIMARY KEY (object_type, object_id)
);
```

`observed_state.health` includes **`unknown`**, and a capability that cannot be
determined is stored as unknown rather than optimistically healthy (D3 §9,
D1 §10.2). A runtime-health change writes `observed_state` and **never**
rewrites `desired_state`.

---

## 11. Transactions and rollback (core)

The persisted, resumable form of the D8 pipeline:
validate → render candidate → validate with target daemon → stage →
atomically activate → verify → retain rollback. State lives in SQLite so a
rollout is auditable and recoverable, and a failed validation leaves the
running configuration untouched.

```sql
CREATE TABLE config_transaction (
  id           TEXT PRIMARY KEY,
  tenant_id    TEXT NOT NULL REFERENCES tenant(id),
  actor_id     TEXT NOT NULL REFERENCES app_user(id),
  summary      TEXT,
  status       TEXT NOT NULL,   -- pending|validated|staged|activated|verified|failed|rolled_back
  -- Roll-up of the validate_target step across all targets. NULL until that
  -- step is reached. It exists so no reader has to infer validation state
  -- from a scan of transaction_step (see §11.1).
  validation_state TEXT,
  started_at   TEXT NOT NULL,
  completed_at TEXT
);

-- Each step of the pipeline, recorded with outcome for the audit + rollback story.
CREATE TABLE transaction_step (
  txn_id     TEXT NOT NULL REFERENCES config_transaction(id),
  step_index INTEGER NOT NULL,
  host_id    TEXT REFERENCES host(id),
  step       TEXT NOT NULL,      -- validate|render|validate_target|stage|activate|verify
  -- Formal outcome vocabulary (§11.1). `passed` is the ONLY value that asserts
  -- this step actually succeeded. 'skipped' is deliberately absent: a generic
  -- skip is exactly how an unavailable check comes to masquerade as a good one.
  outcome    TEXT NOT NULL CHECK (outcome IN
               ('passed','failed','not_applicable','unsupported','substituted')),
  -- Populated when outcome='substituted': which step this stands in for, and
  -- what weaker check actually ran. Never left to inference.
  substitutes_for   TEXT,
  substitute_detail TEXT,
  -- 1 only when the component's OWN validator ran. This column is what makes
  -- "native daemon validation unavailable" impossible to misread as success.
  native_validator_ran INTEGER NOT NULL DEFAULT 0,
  provider      TEXT,            -- which component this step concerned
  -- For providers with no true pre-activation validator: whether provider
  -- policy permits activation anyway. NULL when it does not arise.
  activation_without_native_validation INTEGER,
  exit_code  INTEGER,
  output     TEXT,               -- truncated diagnostic
  started_at TEXT,
  finished_at TEXT,
  PRIMARY KEY (txn_id, step_index, host_id)
);

-- Retained prior configs, so rollback is possible (D8).
CREATE TABLE transaction_rollback (
  txn_id        TEXT NOT NULL REFERENCES config_transaction(id),
  host_id       TEXT NOT NULL REFERENCES host(id),
  scope         TEXT NOT NULL,    -- e.g. the config file/target it replaced
  snapshot_ref  TEXT NOT NULL,    -- retained artifact identifier
  created_at    TEXT NOT NULL,
  PRIMARY KEY (txn_id, host_id, scope)
);
```

### 11.1 Step outcome vocabulary

The pipeline (validate → render → validate with target daemon → stage →
activate → verify → retain rollback, D8) is recorded per step and per target.
Each step lands in exactly one of five outcomes, and the distinction between
them is the point of this subsection:

| Outcome | Meaning | Implies the step ran? |
|---|---|---|
| `passed` | The step ran and succeeded. | **Yes** |
| `failed` | The step ran and failed. | Yes, and it broke |
| `not_applicable` | The step does not apply to *this change* (e.g. no backend changed, so nothing to activate). | No, and nothing was missed |
| `unsupported` | The **provider** does not implement this step at all. | **No — and a capability is missing** |
| `substituted` | A named, weaker check stood in for the real one. | Not the real one; the substitute is recorded |

There is no generic `skipped`. That is deliberate: a single catch-all skip is
how an unavailable validation quietly becomes indistinguishable from a passing
one, and the transaction history then *implies a check happened when it did
not*.

Two supporting columns make the distinction unmissable:

- `native_validator_ran` is `1` **only** when the component's own validator
  executed. A `validate_target` step that could not reach a native validator
  has `native_validator_ran = 0` no matter what the `outcome` string says.
- `substitutes_for` + `substitute_detail` name the stand-in, so a reader always
  knows *what actually ran* instead of inferring it from a status word.

### 11.2 The two worked cases

These are recorded now, before the code exists, because both are properties of
the components (D1 A.1, A.5) rather than of the implementation, and because
they are the cases most likely to be papered over later.

**ldirectord — no native validator, but a real substitute exists.**

ldirectord accepts no validate subcommand (D1 A.1). So `validate_target` is
recorded as `unsupported` with `native_validator_ran = 0`, and a *named
substitute* is recorded alongside it: render, then `perl -c` on the generated
file, then structural checks against the known keyword set. That substitute is
`substituted` with `substitutes_for = 'validate_target'` and a
`substitute_detail` naming the three checks. Activation for ldirectord is a
restart, not a reload, and the pipeline says so rather than implying a smooth
reload.

The distinction that matters: a substitute is *recorded as a substitute*. An
operator reading the history sees "ldirectord has no native validation; these
weaker checks ran instead" — not "validated".

**PPPoE — no validator, and policy decides whether that is permitted at all.**

PPPoE has no validate-then-activate daemon shape (D1 A.5); it is driven by
pppd per session. There is no honest substitute to offer, so `validate_target`
is `unsupported` and stays that way. `activation_without_native_validation` is
then set **only** by explicit provider policy, and it is nullable precisely so
that "policy was never consulted" is distinguishable from "policy said no" and
from "policy said yes".

The rule, stated once and enforced by D8: **a transaction may not reach
`activated` on a target whose validation is `unsupported` unless
`activation_without_native_validation` is explicitly set to 1 by provider
policy.** If policy has not been set, activation is refused — not warned about,
not auto-allowed. The `validation_state` roll-up on `config_transaction` exists
so the TUI and the CLI can surface this in one glance (D1 §10.2) without
scanning steps, and so no reader can see `status = activated` and wrongly infer
that validation ran.

---

## 12. Audit (core)

```sql
CREATE TABLE audit_event (
  id          TEXT PRIMARY KEY,
  tenant_id   TEXT NOT NULL REFERENCES tenant(id),
  actor_id    TEXT REFERENCES app_user(id),
  session_id  TEXT REFERENCES session(id),
  action      TEXT NOT NULL,
  object_type TEXT,
  object_id   TEXT,
  outcome     TEXT NOT NULL,        -- success|denied|failed
  source_addr TEXT,
  before_json TEXT,
  after_json  TEXT,
  txn_id      TEXT REFERENCES config_transaction(id),
  created_at  TEXT NOT NULL
);
CREATE INDEX audit_event_tenant_time ON audit_event (tenant_id, created_at);
CREATE INDEX audit_event_object      ON audit_event (object_type, object_id);
```

Append-only in intent (D3 §6). Every configuration change records actor,
object, before/after, outcome, and transaction.

---

## 13. Secrets references (core; values live in a separate store)

Only **references** are stored here; the secret store and its values are
separate and never returned through ordinary API responses (D3 §5).

```sql
CREATE TABLE secret_ref (
  id          TEXT PRIMARY KEY,
  tenant_id   TEXT NOT NULL REFERENCES tenant(id),
  name        TEXT NOT NULL,
  kind        TEXT NOT NULL,   -- pppoe_password|bind_tsig|tls_key|node_credential|api_token
  store_key   TEXT NOT NULL,   -- opaque key into the separate secret store
  created_at  TEXT NOT NULL,
  rotated_at  TEXT,
  UNIQUE (tenant_id, name)
);
```

---

## 14. Module registry (core)

The registry the TUI derives its sections/actions from (D1 §6.4, D2 §3, §8).

```sql
CREATE TABLE module_registry (
  module_name    TEXT NOT NULL,
  module_version TEXT NOT NULL,
  abi_version    INTEGER NOT NULL,
  provides_mask  INTEGER NOT NULL,   -- capability flags from the descriptor
  requires_mask  INTEGER NOT NULL,
  state          TEXT NOT NULL,      -- loaded|refused|incompatible|disabled
  diagnostic     TEXT,               -- why refused, if refused
  last_seen_at   TEXT NOT NULL,
  PRIMARY KEY (module_name, module_version)
);
```

An incompatible ABI is recorded here with a **clear diagnostic** and
`state='incompatible'` — never loaded optimistically (D2 §6).

---

## 15. What this schema deliberately does not do

- It does not model provider configuration as free-form config text except
  where an explicit `advanced_directives` escape hatch exists (D1 §7.4). The
  structured model is the product; raw text is the exception, stored
  first-class so it is never silently lost.
- It does not fold observed health into desired state. They are separate
  tables with separate lifecycles (§10).
- It does not give the TUI or a module a direct database path. All access
  flows through the core services (D2 §5, D3 §2).
- It does not couple the common service model to any single renderer. The
  renderer is a policy attribute of `load_balancer` (§7), which is what lets
  the same VIP move from ldirectord to HAProxy to a future udpdist without a
  schema change.

No SQL is executed and no code is written against this document pending
review.

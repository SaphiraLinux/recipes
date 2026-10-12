# D9 — Interfaces: TUI, CLI, API/IPC, and deferred web

Status: **design, not implementation.** Companion to D1–D8. D9 is the
interface layer: what an operator and an automation client actually touch.

---

## 1. The four surfaces

```
                    saphira-router core
                           |
                     common API / IPC
                      /             \
                  TUI                CLI --json
           primary human          automation
            interface              interface
                      \             /
                       [ web — deferred, optional ]
```

- **API/IPC** — the single control surface (D1 §3.2). Local by default, via a
  Unix domain socket. Every privileged or configuration operation is reachable
  only through it.
- **TUI** — the primary human interface and the **M1 acceptance criterion**
  (D1 §4). Built on ncurses.
- **CLI** — first-class automation. Every read and write command supports
  `--json`.
- **Web** — a future optional client (module or separate process) consuming the
  same description layer (D2 §4.1). **Not part of M1**, and nothing in D1–D10
  requires it.

### 1.1 One operation surface

The TUI and the CLI are **peers**, not a rich client and a thin fallback. The
API operation registry is the single source of truth for what exists; the TUI
and the CLI each render the same registry. A test asserts they expose the same
operation set and the same authorization outcomes (D5 §7.4).

**No privileged or configuration operation exists only in the TUI.** An
operator must be able to do everything from the terminal, and automation must
be able to do everything the operator can.

---

## 2. The description layer: how both interfaces know what exists

Neither interface hard-codes a provider list. Both derive their structure from
the **module/capability registry** the core exposes via the API (D2 §3, §4.1,
D1 §6.4). A module contributes object types, fields, actions and rendering
kinds; the interface renders them.

This is what makes the platform grow without the interface growing by hand:

- Installing `saphira-router-haproxy` makes HAProxy sections appear in the TUI.
- Removing it makes them disappear cleanly; the rest of the TUI is unaffected.
- The CLI grows new verbs as modules register, with no dispatcher edit.
- A future web client consumes the same description.

The TUI draws; modules describe. This is a hard rule (D2 §4.2) that keeps the
interface consistent and leaves the web door open for free.

---

## 3. TUI design

### 3.1 It's the acceptance criterion

M1 is judged by what an operator can do **from the TUI** (D1 §4). The full
capability checklist lives in D1 §4; it is the TUI's acceptance contract.

### 3.2 What the TUI owns

- Rendering and navigation, from the description layer.
- Forms and prompts, from field definitions.
- Multi-step flows (validate-then-apply, transaction progress, rollback).
- Presentation of the five transaction outcomes and the five capability states
  (D8 §2, D6 §3) **without softening them** — a `substituted` or `unsupported`
  step is shown as such.

### 3.3 What the TUI must never do

- Hold policy, or make a decision the core should make.
- Write state directly, or open the database (D1 §3.2, D4 §1).
- Bypass the API to talk to a component.
- Hide a capability the user lacks — it shows the operation, denied, with a
  reason (D5 §6).

### 3.4 Screen structure (indicative)

```
  login ──> context select (tenant) ──> main
                                              ├── Hosts          (enroll, capabilities, status)
                                              ├── Load balancing (VIP, real servers, health)
                                              │     ├── IPVS / ldirectord
                                              │     ├── HAProxy
                                              │     └── gredist
                                              ├── Network         (bridges, ports, VLANs, PPPoE)
                                              ├── Transactions    (apply, progress, rollback)
                                              ├── Audit           (history, by object / actor)
                                              └── Firewall        (planned module — see D10 §7)
```

The Firewall entry appears **only** when a firewall module is installed; it is
not a hard-coded tab (D1 §6.4). In M1 it does not appear at all, because no
firewall module is installed (D10 §7).

---

## 4. CLI design

```
saphira-router host add | list | show
saphira-router vip add | show | remove
saphira-router real add | remove | enable | disable | drain
saphira-router service status
saphira-router haproxy validate
saphira-router network show
saphira-router vm list
saphira-router dns zone list
```

- **`--json` on every read and write.** This is the automation contract.
- Human output is the default; `--json` switches to machine output. They are
  the same data, differently rendered.
- Exit codes are stable and meaningful: `0` success, non-zero on failure, with
  a distinct code for *denied* (authorization, D5 §6) versus *failed* (the
  operation ran and failed) versus *partial* (multi-target, D8 §6). This lets a
  script distinguish "you may not do this" from "it broke" from "half of it
  worked".

The CLI is a **thin client of the API** — it does not reimplement authorization
or reach the database.

---

## 5. API / IPC

- **Transport:** Unix domain socket, local by default. Private permissions
  (D3).
- **AuthN/AuthZ:** sessions scoped to (user, tenant); every operation authorized
  via the core service (D3 §3, D4; D5 §4).
- **Single write authority:** all mutation goes through the core state service;
  the TUI and CLI never write the database (D1 §3.2, D4 §1).
- **Versioned:** the API is versioned from v1. The CLI and TUI carry the API
  version they speak.
- **Machine-readable:** `--json` output and a stable schema. The API is the
  contract; both interfaces are renderings of it.

---

## 6. Deferred web client

If a web client is ever built, it is an **optional module or separate process**
that consumes the same description layer and the same API as the TUI and CLI.
It adds no capability the terminal does not have. It is out of M1, and no part
of the core, ABI, or schema requires it. (D1 §2, §6.4; D2 §4.1.)

---

## 7. Tests this model must pass

- **Interface parity.** The TUI and CLI expose the same operation set and the
  same authorization outcomes (D5 §7.4).
- **Registry-driven UI.** Installing a fixture module adds a TUI section with
  no TUI source change; removing it removes the section cleanly (D2 §9).
- **`--json` completeness.** Every CLI read and write command has working
  `--json` output with a stable schema.
- **Exit-code semantics.** `denied` ≠ `failed` ≠ `partial` are distinguishable
  by exit code and by a script.
- **No-TUI-only paths.** No operation reachable from the TUI is unreachable from
  the CLI.
- **Honest presentation.** A `substituted` or `unsupported` transaction step,
  and a `unavailable` or `unestablished` capability, are shown as such — not
  rounded up to success or health (D6 §3, D8 §2).

---

## 8. What this model does not claim

- It does not make the TUI a privileged client. It is a client like any other.
- It does not hard-code providers into the interface. They come from the
  registry.
- It does not treat `--json` as a debug dump; it is the automation contract.
- It does not build a web client, or need one.
- It does not soften a `substituted` validation or an `unavailable` capability
  into a clean-looking success.

No implementation code is written against this document pending review.

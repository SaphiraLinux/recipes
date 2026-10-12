# D8 — Configuration transactions, activation and rollback

Status: **design, not implementation.** Companion to D1–D4. This document
formalises the transaction semantics already encoded in D4 §11 and adds the
failure behaviour that makes a control plane trustworthy.

---

## 1. The pipeline

Every configuration change is a transaction, executed as:

```
validate → render candidate → validate with target daemon → stage
        → atomically activate → verify → retain rollback
```

A transaction is **never** an incremental edit of a live configuration. A
candidate is generated, checked, staged, and only then activated. A failed
validation leaves the running configuration untouched — this is the property
that makes the platform safe to point at production.

The pipeline is persisted (D4 §11) so it is auditable, resumable after a
controller restart, and recoverable.

---

## 2. Step outcomes are formal and literal

The five outcomes from D4 §11.1, restated as the normative vocabulary:

| Outcome | Meaning | Step ran? |
|---|---|---|
| `passed` | Ran and succeeded. | **Yes** |
| `failed` | Ran and failed. | Yes, and it broke |
| `not_applicable` | Does not apply to this change. | No, nothing missed |
| `unsupported` | The **provider** does not implement this step. | **No — capability missing** |
| `substituted` | A named weaker check stood in. | Not the real one; substitute recorded |

**There is no generic "skipped".** A catch-all skip is how an unavailable
validation becomes indistinguishable from a passing one. Two columns enforce
this: `native_validator_ran` is `1` only when the component's own validator
executed, and `substitutes_for`/`substitute_detail` name any stand-in.

**The transaction history must never imply a validation happened when it did
not.** Any reader — TUI, CLI, audit, or a human reading the database — must be
able to tell, without inference, which checks actually ran.

### 2.1 The two known cases (D4 §11.2)

- **ldirectord** — no native validate subcommand. `validate_target` is
  `unsupported`, `native_validator_ran = 0`, with a *named* substitute
  recorded as `substituted`: render, `perl -c`, structural keyword checks.
  Activation is a restart, not a reload, and the record says so.
- **PPPoE** — no validate-then-activate shape. `validate_target` is
  `unsupported` with no substitute, and activation is permitted only when
  provider policy explicitly sets `activation_without_native_validation = 1`.

---

## 3. Activation policy

When a target's validation is `unsupported`, whether activation may proceed is
**provider policy** — an explicit, per-provider decision, never a default.

- **Policy default is deny.** If no policy has been set, activation on a
  target with `unsupported` validation is **refused**.
- A policy that permits it must be explicit, is recorded on the step, and is
  visible in the transaction history. "Policy was never consulted" is
  distinguishable from "policy said no" and from "policy said yes" — which is
  why the column is nullable.
- A permitted activation is **not** recorded as validated. It is recorded as
  `unsupported` validation with a permitted activation, so the history remains
  truthful about what was and was not checked.

This is what lets a platform include a component that cannot validate (PPPoE)
without either refusing to manage it or lying about the safety of doing so.

---

## 4. Idempotency and retries

A retried transaction must be safe. Each step carries an **idempotency key**
(a stable hash of the target, the operation, and the intended end-state). On
retry:

- A step already recorded `passed` with the same key is **not re-executed**.
- A `failed`, `unsupported`, or `substituted` step is retried if the operator
  asked for a retry, and the attempt is appended, not overwritten.
- Activation is idempotent: activating an already-activated target is a no-op
  recorded as such, not a second activation.
- Staging is idempotent: re-staging the same candidate produces the same
  result and does not accumulate artifacts.

Retries append history. The record of what went wrong the first time is part
of the audit value, so it is preserved, not cleaned up.

---

## 5. Rollback

- **Every activation retains a rollback artefact** — the prior state of what
  it replaced — before it changes anything (D4 §11 `transaction_rollback`).
  Retention is not best-effort; an activation without a retained prior state
  is not permitted to proceed.
- **Rollback is a transaction in its own right**, not a flag flip. It runs the
  same pipeline against the retained artefact: render the prior state, stage
  it, activate it, verify it.
- **Rollback is not reported as successful until the target state is
  verified.** A rollback that restores an artifact but cannot confirm the
  target reached the prior state is recorded as `failed` or `unverified` — not
  as success. This is the single most important honesty rule in this
  document: claiming a rollback succeeded that did not is worse than not
  rolling back, because the operator stops looking.
- Rollback artefacts are retained for a defined window, and their expiry is
  visible so the operator knows when a transaction is no longer reversible.

---

## 6. Partial multi-node deployment is a first-class state

If a transaction targets several nodes and some succeed while others fail,
that is **not** simply "failed". The transaction must know exactly which
targets changed, which did not, and what reconciliation or rollback is
required. This is why per-target step rows exist (D4 §11).

### 6.1 Per-target state

Each target carries its own step outcomes, so the transaction can answer, at
any time:

- which targets are `in_sync` with the new desired state;
- which are `not_attempted`, `failed`, `partially_applied`, or `unverified`;
- for each, what its rollback artefact is.

A transaction-level status is a **rollup over targets**, and a rollup that
would hide a partial success is not a valid rollup.

### 6.2 Partial is its own state, not a synonym for failed

A transaction that activated on nodea and failed on nodeb is `partial`. The
distinction matters operationally: `failed` suggests nothing changed, while
`partial` means the fleet is now **inconsistent** — nodea is serving the new
configuration and nodeb is not. For a load balancer, that inconsistency is
itself an incident, and the platform says so rather than reporting a tidy
failure.

### 6.3 Resolution of a partial transaction

A partial transaction must be driven to a resolved state. The platform offers,
per target:

- **complete** — retry the failed target (idempotent, §4);
- **roll back** — restore the target to its prior state (§5), verified;
- **leave and report** — accept the inconsistency knowingly, recorded, with the
  affected targets named, so the ongoing state is a documented decision rather
  than a lingering surprise.

Until a partial transaction is resolved, it stays visible as unresolved. The
TUI shows it as needing attention (D1 §10.2), and it feeds D7's reconciliation
as `desired_not_realised` on the affected targets specifically (D7 §4.3).

---

## 7. Activation safety

- **Atomic activation.** Where a component supports an atomic swap (HAProxy's
  reload, OVS via its own transaction semantics), the platform uses it.
  ldirectord activation is a restart, not an atomic reload (D1 A.1), and the
  record reflects that it is a restart.
- **Validate before touching live state,** always. The ordering in §1 is the
  guarantee: a candidate that fails validation never reaches the live
  configuration.
- **Verify after activation,** from the strongest available source (D7 §3.3). A
  verify step sourced only from a weak or stale observation is recorded as
  weak, and does not by itself mark the transaction verified.

---

## 8. What this model does not claim

- It does not claim every component can be validated or rolled back the same
  way. ldirectord and PPPoE genuinely cannot (D1 A.1, A.5), and the history
  says so rather than smoothing it over.
- It does not claim activation is atomic for every component. Where it is not,
  the record says it was a restart.
- It does not report a rollback successful without verification.
- It does not collapse a partial deployment into "failed" and hide the
  inconsistency.
- It does not auto-retry silently; retries are explicit and appended to
  history.

No implementation code is written against this document pending review.

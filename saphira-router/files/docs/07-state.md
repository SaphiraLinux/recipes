# D7 — Desired state and observed state

Status: **design, not implementation.** Companion to D1–D4. Read D4 §10 and
D1 §4 row 12 first.

---

## 1. The rule this document exists for

> Runtime failure must never mutate desired state.

A RIP that goes down, a daemon that stops, a node that reboots — none of these
is a reason to change what the operator asked for. The platform records what
happened in **observed** state and leaves **desired** state alone. This is the
difference between a control plane and an automation loop that quietly
rewrites its own intent.

Concretely, the example from the brief, held exactly:

```
desired:  VIP has backend nodeb enabled
observed: nodeb is DOWN according to ldirectord
```

The second line is information. It is never an instruction to change the
first.

---

## 2. Two stores, separate lifecycles

Per D4 §10, `desired_state` and `observed_state` are separate tables with
separate primary purposes.

| | `desired_state` | `observed_state` |
|---|---|---|
| Holds | what the operator asked for | what the platform last saw |
| Written by | operator actions, through transactions | collectors/observers |
| Changes when | someone changes intent | reality changes |
| Never changed by | a health check, a failed deploy, a reboot | anything but a collector |
| Trust | authoritative | **evidence, possibly stale** |

Observed state is a **claim about reality at a point in time**, not a fact.
That is why §3 exists.

---

## 3. Freshness, time and source are part of the observation

An observed row is only meaningful with its provenance. D4 §10 already stores
`observed_at` and `source`; this document fixes the semantics and adds the
dimension that makes `DOWN` and `UNKNOWN` and *stale* distinguishable.

### 3.1 Health values

```
healthy | degraded | down | draining | unavailable | unknown
```

- `unavailable` — **we know we cannot determine this**, and we know why. E.g.
  HAProxy observed state with no runtime socket configured (D1 A.2). This is a
  *known* condition, and the platform says so explicitly rather than guessing
  (D1 §10.2, D3 §9).
- `unknown` — we have no observation at all, or the last one could not be
  interpreted.

`unavailable` and `unknown` are deliberately different: one is a diagnosed
absence, the other is an absence of knowledge. An operator needs to tell them
apart, because they imply different actions.

### 3.2 Freshness is separate from health

Health answers "what did we see?"; freshness answers "how long ago, and is
that still standing?" They are orthogonal, and conflating them produces a
control plane that reports a node as `healthy` from a three-hour-old probe.

```
fresh  — observed_at within the object's staleness budget
stale  — beyond the budget, but the last observation is still recorded
expired— beyond a hard horizon; the row is retained but no longer displayed
         as current, and the object is treated as unknown for decisions
```

The practical consequence: **a stale observation is never promoted to a
current claim.** An object whose only evidence is `stale` is reported as stale
health, and any decision that depends on it (deployment eligibility, traffic
affecting action) treats it as unknown. Freshness budgets are per object kind
— a health check's budget is short, a package inventory's is long.

### 3.3 Source is recorded and can be weak

`source` names the collector, and a source can be weaker than another. A
`ping`-based inference and a direct daemon query are both observations; the
latter is stronger. Where two sources disagree, the platform records both and
reports the disagreement rather than silently picking the convenient one. D8
depends on this: a `verify` step sourced from a weak observation is not the
same evidence as one from the daemon itself.

---

## 4. Explicit reconciliation, not magic

Reconciliation compares desired against observed and **proposes** a diff. It
does not act on its own.

```
  desired_state  ──┐
                   ├──▶  RECONCILE  ──▶  proposal (a diff)  ──▶  operator/policy
  observed_state ──┘                        │
                                            └──▶ no automatic application, ever
```

### 4.1 The proposal classifies every difference

| Class | Meaning |
|---|---|
| `in_sync` | desired and observed agree |
| `desired_not_realised` | the operator asked for it; reality does not have it |
| `realised_not_desired` | reality has it; the operator never asked (an orphan) |
| `drift` | both exist but disagree in detail |
| `undeterminable` | observed state is unknown/stale, so no comparison is possible |

`undeterminable` is a first-class class. When observation is stale or
`unavailable`, reconciliation says **"cannot determine"** rather than assuming
agreement and reporting `in_sync`. Silently reporting a stale node as in-sync
is the most dangerous possible failure of a control plane, because it converts
an unknown into a false all-clear.

### 4.2 Reconciliation never mutates desired state

This is the rule of §1 restated at the mechanism level. Reconciliation reads
desired and observed; it writes a **proposal**. Applying a proposal goes
through the ordinary transaction pipeline (D8) with its own authorization,
validation, audit and rollback. A reconciler with no proposal accepted changes
nothing.

`realised_not_desired` deserves particular care: something exists in reality
that the operator never asked for. The platform **reports** it and does not
delete it, because it may be there for a reason outside the platform's view.
Auto-deleting unrecognised real-world state is how a control plane causes an
outage it then reports as a fix.

### 4.3 Drift caused by a failed transaction is a special case

If a transaction partially failed (D8 §6), the resulting difference is
`desired_not_realised` on some targets and `in_sync` on others. That is a
**partial** state, not generic drift, and it is surfaced as such — the
operator is told which targets are affected rather than being handed a global
"out of sync" that obscures the actual damage.

---

## 5. What the TUI shows

The TUI (D1 §4 row 12) must let an operator see desired and observed
**separately**, and the display mirrors the model:

- desired state: what the platform will converge to
- observed state: what it last saw, **with** its timestamp, source and
  freshness
- reconciliation: the current proposal, or "in sync", or "cannot determine"

An operator must never have to infer intent from runtime output. This is also
why D1 §10.2's gap reporting surfaces here: a node with `unavailable`
observation shows as unavailable-with-reason, never as healthy-by-default.

---

## 6. What this model does not claim

- It does not claim observed state is accurate in real time. It is a
  timestamped claim from a named source, possibly stale.
- It does not auto-converge. Convergence is an explicit, authorized,
  transactional act.
- It does not treat "no observation" as "no problem." It treats it as unknown.
- It does not delete real-world state it did not create (§4.2).
- It does not let a health check, a failed deployment, or a reboot rewrite an
  operator's intent.

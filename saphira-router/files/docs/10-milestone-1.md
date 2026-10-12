# D10 — Milestone 1 acceptance and packaging

Status: **design, not implementation.** Final document in the D-series. Read
D1 (acceptance criteria, conventions, prerequisites) and D9 (interfaces) first.

---

## 1. What M1 is

M1 delivers a working multi-tenant control plane that an operator drives from
the **terminal**. It is accepted when the D1 §4 checklist is completable from
the TUI, and the components below are driven correctly and honestly.

M1 scope, in the order the layers depend on each other:

1. users / tenants / RBAC (D5)
2. host enrollment and capability discovery (D6)
3. LVS + ldirectord (D1 A.1, D4 §7)
4. HAProxy basic L4 / L7 (D1 A.2, D4 §8)
5. gredist (D1 A.3)
6. OVS / saphira-network (D1 A.4, D4 §6.1)
7. rp-pppoe (D1 A.5, D4 §6)
8. status / audit / rollback (D7, D8, D4 §10–§13)
9. API + CLI + TUI (D9, D2)
10. basic (TUI) interface — the acceptance surface (D9 §3)

**BIND9 and libvirt are represented in the schema now** (D4 §9) so it does not
paint us into a corner, but they do not block the first working load-balancer
control plane and are not M1 acceptance requirements.

**Firewall is not in M1** — see §7.

---

## 2. Acceptance topology

### 2.1 Controller / test host

**Unresolved, deliberately.** `hatchling` and `hatched` are both real
hostnames *and* both the names of package repository locations in existing
Saphira usage. No address has been supplied and **none is guessed**. The
controller host is a **configurable parameter** of the M1 acceptance run. When
an address is supplied it is recorded here (D1 Appendix C).

### 2.2 Managed nodes

Verified reachable from the build host, all Saphira-D Linux 0.2, `x86_64`,
systemd:

| Node | Address | Present | Absent |
|---|---|---|---|
| nodea | `172.16.7.100` | `openvswitch`, `saphira-gredist`, `saphira-network` | `ipvsadm`, `resource-agents`, `haproxy`, `rp-pppoe`, `bind`, `libvirt` |
| nodeb | `172.16.7.110` | (as nodea) | (as nodea) |
| nodec | `172.16.7.120` | (as nodea) | (as nodea) |

These nodes deliberately lack the LB stack. That is a **feature of the
acceptance run**, not a gap: it is a live demonstration that the platform
**refuses** to place an object on a node that lacks a required capability, and
that the discovery matrix (D6 §3) reports the difference honestly. Promoting
the LB packages onto them is part of exercising M1, and doing so raises their
capability states through the probes — never by assumption (D6 §3.1).

---

## 3. Acceptance is the operator journey

M1 is accepted when an operator, **from the TUI alone** (no browser, no
hand-editing generated config), can:

| # | Capability | Spec |
|---|---|---|
| 1 | Log in and select tenant / context | D5, D9 |
| 2 | See controller and managed-host status | D1 §7, D7 |
| 3 | Enroll / view hosts and their discovered capabilities (with states) | D6 |
| 4 | Create / edit / remove a virtual service | D4 §7, D8 |
| 5 | Add / remove / enable / disable / **drain** real servers | D4 §7, D5 §2.1 |
| 6 | Select and configure IPVS + ldirectord | D1 A.1, D8 §2.1 |
| 7 | Configure basic HAProxy L4 / L7 | D1 A.2, D4 §8 |
| 8 | Inspect / edit M1 HAProxy ACL / rule / rewrite objects | D4 §8 |
| 9 | Manage gredist services | D1 A.3 |
| 10 | Inspect / manage OVS bridges, ports, VLANs | D4 §6.1 |
| 11 | Configure / view PPPoE | D4 §6 |
| 12 | See **desired** separately from **observed** health, with freshness | D7 |
| 13 | **Validate** a change before applying it | D8 |
| 14 | **Apply** it | D8 |
| 15 | See success / failure, and *why* (the five outcomes) | D8 §2 |
| 16 | Inspect audit history | D4 §12 |
| 17 | **Roll back** a previous transaction (verified) | D8 §5 |

Plus the cross-cutting properties that must hold throughout:

- Multi-tenant isolation, with the cross-tenant negative tests (D5 §7.3).
- New capabilities are inert until granted (D5 §5).
- Capability is probed, never inferred (D6 §3.1).
- Failed validation leaves the running configuration untouched (D8 §1).
- Partial multi-node deployment is a visible, resolvable state (D8 §6).
- Gaps are reported, not hidden (D1 §10.2).

---

## 4. Packaging plan — `/recipes/saphira-router`

Follows the Saphira recipe contract (D1 §9). Recorded here so the packaging
shape is settled before code exists.

### 4.1 Packages

```
saphira-router                    core daemon + API/IPC + CLI + TUI + docs
saphira-router-ipvs               mod_ipvs.so
saphira-router-ldirectord         mod_ldirectord.so
saphira-router-haproxy            mod_haproxy.so
saphira-router-gredist            mod_gredist.so
saphira-router-ovs                mod_ovs.so
saphira-router-pppoe              mod_pppoe.so
saphira-router-bind9              mod_bind9.so          (schema-representing)
saphira-router-libvirt            mod_libvirt.so        (schema-representing)
saphira-router-import-loadbalancerorg   mod_import_loadbalancerorg.so
saphira-router-import-f5                mod_import_f5.so
```

Each module is independently installable/removable; the core is usable with
none installed (D2 §7).

### 4.2 Recipe facts

- **Nine mandatory metadata keys** (D1 §9): `pkgname pkgver pkgrel pkgarch
  pkgdesc license origin repo url`; `pkgname` must equal the directory name.
- **Exactly two functions**: `recipe_build()` and `recipe_install()`. Nothing
  else is invoked.
- **`pkgrel >= 1`, never r0**; bump on every payload change.
- **Dual init** for the core daemon: `/etc/init.d/saphira-router` and
  `/usr/lib/systemd/system/saphira-router.service`. **Ship both, enable
  neither** — enabling is a profile decision.
- **Service identity** via `files/accounts.d/saphira-router`. UID/GID **127+**
  are free (122/123/124/125/126 taken; D1 §9). The core runs **unprivileged**
  (D1 §8), so it needs no capabilities; anything privileged runs at the
  drone/helper boundary, not here.
- **Config:** `/etc/saphira/saphira-router/`, `0750 root:root`, flat
  `KEY=VALUE`. **State:** SQLite under a core-owned state directory, with
  permissions that reflect the single-write-authority model (D4 §1) — the
  database is not writable by the TUI/CLI user.
- **Headless / non-merged-`/usr`** rules apply in full (D1 §9).
- Modules are installed to a **core-owned module directory**, loaded by
  absolute path (D2 §7).

### 4.3 Dependency set (D1 §9.1)

| Need | Package | Note |
|---|---|---|
| Language | C11 | `gcc make` at build |
| State | `sqlite` | |
| Passwords | `libargon2` | argon2id reference impl, already packaged |
| TUI | `ncurses` | wide; ships libncursesw, libformw, libmenuw, libpanelw |
| JSON | `json-c` | packaged, widely exercised (bind, clamav, frr, libvirt, …) |
| TLS (transport) | `openssl` | for the IPC/auth if needed |

Deliberately **no nginx, no PHP, no web server, no Go** (D1 §9.1). The TUI is
a terminal client, so there is no HTTP stack in the core.

### 4.4 Module packages depend on their components, not the reverse

`saphira-router-haproxy` depends on `haproxy`; `saphira-router-ldirectord`
depends on `resource-agents` (which is where ldirectord lives, D1 A.1). The
core depends on **none** of the components — it is component-agnostic. This is
what lets the core run with no modules and lets a component be added or
removed without a core change (D2 §9).

---

## 5. Build discipline

- Builds go through `saphira-build`; **`buildpkg` is not run directly**
  (D1 §9, Saphira convention).
- Vendored sources land in `files/` with a `.sha256` sidecar; **no invented
  URLs**.
- Verification suites run before any commit; commit messages use
  `area: lowercase summary`.
- Commits land on a feature branch and are reviewed, as with the current
  D-series.

---

## 6. Known external prerequisites (unchanged)

D1 Appendix B's seven gaps stand and are **not** fixed by this project. M1 is
designed to *report* them honestly, not to repair them:

- HAProxy observed state `unavailable` (no runtime socket).
- ldirectord validation `unsupported`, with a named substitute (D4 §11.2).
- ldirectord service-surface defects (OpenRC status, systemd PIDFile).
- gredist no service integration, unpublished revisions.
- `saphira-lb-healthchecks` packaged but unwired — the router is its natural
  first consumer and *selects/configures* it rather than reimplementing it
  (D1 A.8).

---

## 7. Firewall: a planned module, explicitly M2+

**Firewall is a planned module, not an M1 acceptance requirement.** The D9
Firewall screen does not appear in M1 because no firewall module is installed.

`mod_nftables` (and OVS interface rules) is **M2+**, for four reasons recorded
now so the decision is deliberate rather than deferred-by-omission:

1. **Saphira already draws a classification/enforcement line.** The shipped
   `saphira-classification.nft` classifies traffic into marks/sets/verdict maps
   at priority −150, and `/etc/nftables.conf` enforcement chains consume them
   and own the policy. A router feature must respect that existing split
   rather than conflate classification with enforcement. The integration point
   is **`/etc/nftables.d/`**, the site-specific include dir — **not** editing
   the shipped policy in place.

2. **nftables and OVS must remain visibly distinct policy layers.** A packet
   traverses both. Surfacing them under one "firewall" menu invites double-fired
   rules and baffling precedence. They are modelled as distinct layers with
   explicit collision/precedence rules (D9 §2), not one blended concept.

3. **Host-level firewall state is a shared physical resource and needs an
   explicit multi-tenant ownership model before tenant users can mutate it.**
   Every other object in the model is *logical* and tenant-namespaced; a host
   firewall rule is shared. D5's per-tenant isolation assumes per-tenant rows,
   which does not hold for one shared ruleset on a shared host. This must be
   solved first.

4. **When firewall design begins, evaluate — and do not decide implicitly
   while implementing the module:**
   - host-wide, admin-only rules;
   - tenant-scoped named tables/chains;
   - router-managed dispatch/ordering;
   - an explicit capability split (e.g. `firewall.write.host` vs
     `firewall.write.tenant`);
   - collision/precedence rules with OVS policy.

`mod_nftables` is, however, a strong **reference implementation** of the D8
pipeline: `nft -c -f` is a true side-effect-free pre-flight validator (like
`haproxy -c -f` and `named-checkconf -z`), and nftables 1.1.6-r9 is built
`--with-json`, so real observed state and drift detection are available. The
transaction model applies here with **higher** stakes, not lower: a bad
firewall rule is a traffic outage or a security exposure (D8 §5, §7).

---

## 8. What this model does not claim

- It does not claim M1 repairs the components beneath it (D1 §10.1, §6).
- It does not claim the controller host is known (§2.1).
- It does not claim every component can be validated or rolled back the same
  way; the history says so per component (D8 §2.1).
- It does not include firewall (M2+), and does not decide the tenant firewall
  model implicitly (§7).
- It does not deliver a web client; the TUI and CLI are the interfaces (D9).

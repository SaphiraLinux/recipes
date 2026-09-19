# saphira-permissions V1 — architecture

System metadata reconciliation for Saphira. V1 implements declared
filesystem state convergence; process confinement and learning
machinery are explicitly out of scope (names reserved below,
documentation only — no V1 tool parses them).

## Authority (distributed, never duplicated)

| Source | Owns |
|---|---|
| APK installed database (`/lib/apk/db/installed`) | packaged paths, modes, installed-package scope |
| `accounts.d` / `ensure-identity.sh` | users/groups, identity-owned paths |
| `fhs.d` / `ensure-fhs` | runtime/service filesystem structure |
| `caps.d` / `ensure-caps` | file capabilities (APK records no xattr/cap field) |
| `saphira-baselayout` | canonical FHS roots, shared override library |
| `override.d` | administrator pins/ignores (wins over packages) |

No SQLite in V1. No second inventory of the installed database.

## Scope

Installed scope is the packages actually present in the target's
APK installed database — the installed dependency closure of the
`/etc/apk/world` root selection — never world entries alone, never
uninstalled packages, never `/usr/local` (outside distribution
management).

## Tools

- `ensure-identity.sh [--disable|--check] FRAGMENT` (baselayout):
  users/groups/state-dir/file convergence; `--check` is drift-only.
- `ensure-fhs [--root PATH] [--check] FRAGMENT` (baselayout):
  runtime structure; `--root` retargets beneath a mounted root
  (also honours `$SAPHIRA_ENSURE_ROOT`).
- `ensure-caps [--root PATH] [--check] FRAGMENT`
  (saphira-permissions): `cap <abspath> <capspec>` stanzas;
  `capspec` is libcap text (`cap_net_bind_service+ep`), names
  validated against the pinned 41-capability list.
- `ensure-permissions --system [--root PATH] [--check|--apply`
  (saphira-permissions): the explicit full-system operation.
  Default is `--check`. Orchestrates per-package fragments in
  sorted order (identity, fhs, caps — sub-tools stay authoritative,
  nothing reimplemented), converges installed-database claims, runs
  the undeclared-capability sweep over `/bin /sbin /lib /usr`,
  verifies sysusers-native identities, audits overrides.
  `--apply` converges maximally (failures recorded, never
  abortive). Package transactions never invoke it.

## Declaration grammars

`caps.d/<output>` ships to `/usr/share/saphira/caps.d/<output>`:

```
cap <abspath> <capspec>
```

`override.d/*.conf` live in
`/etc/saphira/permissions/override.d/` (administrator-owned;
apk-protected; no payload may populate):

```
ignore <abspath>
pin <abspath> <owner> <group> <mode>
pin-cap <abspath> <capspec>
```

Overrides never add claims: a rule fires only for a path already
claimed by an installed declaration (or the installed database).
`ignore` skips convergence (leaf only, never recursive); `pin`
substitutes ownership/mode; `pin-cap` substitutes capabilities and
additionally protects its path from the undeclared-cap sweep
(protection, not convergence). Duplicate rules fail closed.
Unmatched rules warn in `--system` (inert, check spelling/scope).

## Safety contract

Exact-path, leaf-only, non-recursive. Symlinks never followed,
never converged, refused loudly. Protected roots
(`/ /usr /var /etc /bin /sbin /lib /run`) can never be claimed.
One package owns each claimed path (exact-path union at publish;
same-payload-target rule for caps). Protected configs (`/etc` +
`protected_paths.d`) converge but report as `protected:`.
Missing packaged files warn only (content is apk's domain).
`--check` never mutates (the `rmdir` emptiness probe restores
metadata it disturbs).

## Capabilities

`setcap` state from builds is captured into `caps.d` at packaging
time (makepkg validates: absolute normalized path, regular file
shipped in the same payload, known capability names, no duplicate
paths). Generated install/upgrade callers run
ensure-identity → ensure-fhs → ensure-caps. No caps deinstall
(capabilities die with their files). The sweep strips
capabilities no installed declaration covers.

## Relationship to apk audit/fix

`apk audit --system --check-permissions` detects packaged-path
metadata drift offline from the same installed database, and
`apk fix --directory-permissions` repairs directory metadata
offline. They remain useful as an independent cross-check — but
they are not the reconciliation authority, for four reasons
established against apk-tools behaviour and source:

1. apk's database carries no file-type bits (modes are masked to
   07777 at archive read), no non-root ownership (payloads are
   root:root by construction), no runtime paths, no capabilities,
   and no overrides. Converging from it alone would restore the
   wrong owners on every identity-owned path.
2. Fragment declarations intentionally override database records
   (fresher Saphira intent). A healthy system shows
   fragment-explained `m` lines under apk audit; treating audit
   output as drift input would fight declared state.
3. `apk fix <pkg>` reinstalls from archives and silently skips
   (exit 0) when they are unavailable. ensure-permissions repairs
   all metadata from on-system authority with honest exit codes,
   fully offline; only content restoration needs archives.
4. After any `apk fix`, re-run fragment convergence
   (`ensure-permissions --system --apply`): fix restores database
   values, which may predate fragment intent.

`apk fix <pkg>` stays the content-restoration path (checksum and
deletion cases) with a repository available.

## Exit-code contract

Every reconciler reports the same three outcomes; orchestrators
depend on the distinction:

- `0`: converged (mutating modes) or clean (`--check`).
- `1`: drift found (`--check`), or failure (mutating modes).
- `2`: execution error in `--check` mode — the fragment could
  not be assessed at all (malformed input, safety refusal,
  unknown identity, unreadable target).

`ensure-permissions --system --check` counts exit 2 children
separately: any child failure suppresses the normal summary and
replaces it with a failure banner (`--system check FAILED:
... results incomplete, NOT a clean bill`), exiting 2 itself.
A dead child can never hide inside a success-style report.
Apply mode records every nonzero child as a failure with its
exit code and continues maximally.

Operational note: never trust a bare pipeline status — `cmd |
grep` reports grep's exit. Capture `PIPESTATUS[0]` (bash) or
redirect to files before filtering.

## Operational sequence

Audit and recovery compose three independent tools; order matters
because each layer's authority sits on top of the previous one:

```
apk audit --system --check-permissions
    = independent packaged-state audit (metadata + content
      drift against the installed database; fragment-explained
      `m` lines are expected, not alarms)

apk fix <pkg>
    = content restoration when the package archive is available
      (reinstalls; restores database values, which may predate
      fragment intent)

ensure-permissions --system --apply
    = restore Saphira intent on top, including identities,
      runtime paths, capabilities and overrides
```

Never trust `apk fix` exit 0 alone as proof that unavailable
package content was restored: fix silently skips packages whose
archives cannot be fetched (exit 0, nothing repaired). Missing
packaged content is ensure-permissions' warning class precisely
because fabrication is worse than an honest gap.

## Reserved future names (documentation only)

`saphira-access` (confinement / observation / explanation) stays a
separate concern from `saphira-permissions` (reconciliation /
declared metadata). The package declaration schema reserves —
without implementing or parsing — the sections `identity`,
`paths`, `capabilities`, `confinement{profile, mode}`, and the
per-service modes `enforce / audit / learn / off`. A field
accepted by a V1 tool always has real semantics; nothing here is
 parsed inertly.

Hardening sequence (init-independent first): complete
least-privilege/capabilities work, then seccomp evaluation with
audit-first rollout, then init-specific sandboxing where useful
(systemd directives are variant hardening, never the canonical
model — every control is classified init-independent /
systemd-specific / OpenRC-specific / equivalent), and only then
AppArmor enablement evaluation. No SELinux. No ACL authority.
Landlock is a complementary launcher primitive, not central
policy.

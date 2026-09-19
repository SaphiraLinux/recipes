# RECIPE_RULES.md — hard rules for agents and operators

These rules are binding. They exist so that recipe work is always
reproducible, rootless, and leaves the running controller host (Egg)
untouched.

## Where things live

- Package recipes are created and edited in `/recipes` — nowhere else.
- All build output and temporary build state lives in `/build` (workspaces
  `/build/PACKAGE.buildpkg`, ccache, staging). Never build inside `/recipes`,
  never build directly in source trees, never scatter build state elsewhere.
- `/out` holds repository output and `/out/stage4/incoming` holds unsigned
  `*-ready` transactions. Nothing else is a build destination.
- Upstream source archives live IN the recipe collection:
  `<pkg>/files/<basename>` plus a `<basename>.sha256` sidecar
  (`<sha>  <basename>`, `sha256sum -c` compatible). The local repo is
  self-contained; the public GitHub mirror stays pure-text (its export
  filter excludes archives) and public builders fetch via the recipe URLs.
- Host `/tmp` is never Saphira scratch: not for archives, not for work,
  not for tests. Tool and test scratch lives under `SAPHIRA_TMPDIR`
  (`/build/tmp` default); test suites run hermetic under their own
  `$test_root`. The isolated build namespace keeps the POSIX `/tmp` name
  for tool compatibility, but it is bound to per-workspace stage storage
  (visible under `/build`, disposed with the workspace), never host /tmp.

## Who builds

- **Agents (opencode / GLM / any LLM session) do NOT run `buildpkg`.**
  Builds are performed exclusively by the saphira-builder service (the
  daemon driving `buildpkg` -> `resolvepkg` -> `buildpkg-single`; the last
  is an internal namespace worker, never invoked directly).
- Agents may: create/fix recipes, commit, request a build (e.g. via the
  saphira-build queue), read retained `/build/PACKAGE.buildpkg` logs and
  `plan.json` for diagnosis, and test built artifacts locally in scratch
  (e.g. `apk --usermode --root /tmp/...`).
- If a build must be verified, hand it to saphira-builder and check the
  result afterwards. Do not babysit long builds in an agent session.

## Saphira builder immutability rule

Package, recipe, porting, dependency, feature, and application work MUST NOT
modify the Saphira build infrastructure.

Without explicit author approval for a builder-specific task, agents MUST NOT
change:

- buildpkg
- buildpkg-single
- resolvepkg
- saphira-builder service/controller
- package_builder.sh or equivalent controller configuration
- package splitting/resolution machinery
- repository publication/signing machinery
- builder sandbox/overlay behaviour
- builder dependency-resolution semantics

A recipe that cannot be expressed using the existing build system is NOT
permission to modify the build system.

Instead:
1. report the exact limitation;
2. demonstrate why the existing machinery cannot express the requirement;
3. propose the smallest builder change separately;
4. wait for explicit author GO.

Builder behaviour that exposes a recipe/test failure must not be weakened to
make the recipe pass.

The author alone decides when Saphira build infrastructure changes.

## Bubblewrap boundary

- Every build runs inside the existing Bubblewrap sandbox
  (`bwrap --unshare-all --uid 0 ...`) driven by the controller scripts.
  The fake-root uid 0 exists only inside the namespace.
- Never bypass Bubblewrap with ad-hoc host builds, and never "just test"
  a compile on the host: if it did not go through bwrap, it did not build.
- Failed workspaces are retained diagnostic evidence with a trusted FAILED
  marker; retry is marker-gated. Clear blockages only via `cleanpkg` or by
  moving a workspace aside visibly — never delete or overwrite by hand.

## Egg is never touched

- Egg is the running Saphira v0.1 controller host. It is not a scratch
  machine, build target, or staging area.
- Never install packages on Egg, never run `installpkg` outside the
  explicit admin boundary, never use sudo/root in the build path, never
  create directories at `/` (the build root is `/build`, which already
  exists and is writable).
- Agent shell work stays in `/recipes`, `/build`, `/out`, and
  `~/worktmp`. Never stage work in `/tmp` (wiped on reboot, shared,
  invisible): downloads go straight to `<pkg>/files/`, scratch to
  `SAPHIRA_TMPDIR`.

## ccache

- Compiler cache lives inside the build scratch (`/build/ccache`, bound to
  `/ccache` inside the namespace by the controller). It speeds up repeated
  native builds and never leaves `/build`.
- Do not point `CCACHE_DIR` elsewhere; do not reuse an Egg-host ccache.

## Dual init system policy (mandatory for service packages)

Saphira is openrc by default but can also run systemd. Every package that
ships a service (daemon) must provide BOTH formats:

- openrc: `/etc/init.d/<servicename>`
- systemd: `/usr/lib/systemd/system/<name>.service`

Ship both unconditionally in the package; unit files are inert when systemd
is not installed. The service script may optionally check for systemd at
runtime. Never ship one format without the other. Units must use the
destination-system paths (`/usr/lib/systemd/system/`), not build-root paths.

## Service identity policy (packages create their users at install time)

The base seed (`saphira-baselayout` `accounts.tsv` + `apply-accounts.sh`)
covers virgin-rootfs assembly only. It is NOT the authority for package
identities: every service package declares its own identities in
`files/accounts.d/<pkgname>` and creates them at install time via the
platform reconciler (`ensure-identity.sh`, invoked from makepkg-generated
`post-install`/`post-upgrade` scripts). Recipe authors declare identities
only — never hand-written scripts, never `useradd` in services.

UID/GID namespace (operator-locked):

- `0..199` — preferred Saphira package/service identities.
- `200..887` — reserved package/system expansion and documented legacy
  exceptions. Accepted, but the build and the publish gate both emit a
  notice, and the fragment must document the exception (comment in the
  fragment plus a note in the recipe).
- `888..999` — local/admin-created service identities. Saphira packages
  must not allocate here. The repository never hands these out and the
  reconciler never creates in them. A hand-provisioned local account
  (e.g. qmail's fixed IDs) with attributes matching a declaration
  converges silently instead of blocking the install.
- `1000+` — human/local users (firstboot territory, never packages).

`root`, `wheel`, `spokes`, and IDs 0–2 are foundation reservations,
typed by kind: the USER `root` and UID 0 are refused; the GROUPS
`root`, `wheel` and `spokes` and GIDs 0, 1 and 2 are refused, as is
anchoring any service user to those groups as primary. (`spokes` is
group-only: a user merely named `spokes` is not forbidden.)
The refusal is enforced at all three layers: `makepkg` fails the
build, the publish gate refuses the transaction, and the helper
refuses in both ensure and disable modes (validation and apply),
always before any write, with byte-identical databases on refusal.
Root provisioning belongs exclusively to the base seed and
firstboot.

Fixed IDs are the norm: declare whatever stable ID the service needs
inside `0..199` (upstream canonical IDs preferred, e.g. dbus
`messagebus:81`, man `man:65`). The publish gate keeps the union
collision-free; one package owns each declared identity, and a
declaration identical to the base seed converges (allowed) while a
conflicting one refuses.

Fragment stanza reference:

- `group <name> <gid>` — declares the group.
- `user <name> <uid> <primary-group> <home> <shell>` — declares the user.
- `dir <path> <mode> <owner> <group>` — state directory: created when
  missing (leading components with default modes), leaf reconciled to
  the declared mode/ownership, never walked.
- `file <path> <mode> <owner> <group>` — install-time file ownership:
  the reconciler sets the declared mode/ownership on a file the
  package itself ships (e.g. `file /var/qmail/bin/qmail-queue 04711
  qmailq qmail`). The target must exist in the payload and must be a
  regular file: missing paths, symlinks (chown would follow onto
  another package's target), directories, fifos, and other specials
  all fail closed at build, and again live (APK payloads cannot carry
  specials at all — runtime fifos such as qmail's queue trigger are
  created with ownership by the service start_pre instead).
  Owner/group must be identities the same
  fragment declares, or the `root`/`0` built-in, which needs no
  declaration; bare numbers besides `0` are refused so every other
  reference stays a converge-checkable name. The publish gate
  re-checks this (same-fragment-or-root) and refuses transactions
  whose file stanzas name undeclared identities. Disable mode
  ignores file stanzas entirely: files are never walked, chowned,
  or removed on `apk del`.

The lifecycle is complete in the install direction and sanitizing in
the removal direction. `apk add`/`apk upgrade` run the generated
post-install/post-upgrade callers (ensure: group, user at canonical
ID, locked shadow, nologin shell, state dirs). `apk del` runs the
generated post-deinstall caller, which embeds the validated
declaration (the payload fragment is already gone at that point) and
invokes the helper in disable mode: a historical account that still
matches its declaration is forced locked with shell restored to
nologin, while the user, the group, the fixed IDs, and all state are
retained and never recycled. Strict on creation, conservative on
removal: install/upgrade fail closed on any UID/GID mismatch, but
deinstall never blocks on drift - a declared name that exists with
different UID/GID (or an unverifiable primary group) is foreign:
warned, left byte-untouched, exit 0. Once reality no longer matches
the declaration, removal loses authority over that identity; deinstall
never renumbers anything. Reserved identities (root/UID 0, foundation
groups) stay fatal in both modes. Any future destructive purge is a
separate explicit operation, never ordinary `apk del`.

Recognised history lives in a legacy sidecar,
`files/accounts.d/<pkgname>.legacy`, beside the fragment:

- `legacy user <name> <old-uid> <old-gid>` and `legacy group <name>
  <old-gid>` record the past for identities the sibling fragment
  declares (nothing else qualifies, ever; past and present must be
  disjoint; reserved identities can never be legacy).
- When ensure meets a present identity exactly matching a legacy
  entry, install stays blocked (non-interactive installs never
  migrate) but the error names the recognised past and the repair:
  `saphira-identity reconcile <pkg>`.
- `saphira-identity reconcile` migrates account-database records
  only (`passwd`/`group`, plus `gshadow` rows when present; shadow
  rows are name-keyed and untouched; filesystem ownership is entirely
  outside the mechanism). Dry-run by default, `--apply` mutates under
  the account lock with a timestamped backup; already-migrated and
  absent entries are clean no-ops; occupied targets and unrecognised
  states refuse before any write.
- Purged-package recovery: `apk add --no-scripts <pkg>` lays the
  declaration without running scripts, `saphira-identity reconcile
  <pkg> --apply` migrates, `apk fix <pkg>` re-runs the scripts and
  converges.

## Filesystem invariant (no FHS directory may be a symlink or alias)

No symlink may substitute for an FHS directory in Saphira. Period.

- `/run` is a real directory; `/var/run` is a separate real directory.
- `/usr`, `/var`, `/bin`, `/sbin`, `/lib`, etc. are real directories.
- Compatibility aliases are not part of the filesystem design.

FORBIDDEN examples: `/var/run -> /run`, `/run -> /var/run`,
`/usr/var` as prefix/configure fallout, any symlink used to
substitute one FHS directory for another.

This rule concerns the filesystem/FHS layout. It does not prohibit
normal functional symlinks created inside packages or runtime trees
where a symlink is genuinely the object being represented.

Service runtime placement follows from the invariant: ordinary
packaged-daemon PID/socket/state paths live under
`/var/run/<service>/`. Base/boot runtime plumbing (systemd, udev,
user, credentials, varlink, mount, log, lock, tmpfiles.d, blkid,
agetty.reload, saphira-network, the iproute2 `/var/run/netns`
convention) stays under `/run`. Never treat a path as correct
merely because it historically resolved through a `/var/run ->
/run` alias: that symlink hid package bugs.

`/var/run` holds volatile runtime state but is a real directory on
the root filesystem (no tmpfs mandate: mounting on the pathname
before reconciliation risks following the historical alias). Boot
convergence handles stale volatile state per declaration.

## FHS migration declarations (fhs.d, mirrors accounts.d)

A corrected package payload fixes fresh installs only. Installed
systems converge on upgrade through per-package declarations plus a
global reconciler — the same ownership split as accounts.d:

- `saphira-baselayout` owns the Saphira-native reconciler
  `/usr/libexec/saphira/ensure-fhs` and the global filesystem
  declaration (the historical `/var/run` symlink, `/usr/var`
  residue, required core directories).
- Every affected recipe owns its package-specific historical
  migration in `files/fhs.d/<output>`, installed to
  `/usr/share/saphira/fhs.d/<output>`. The package that published
  the bad path owns the declaration converging it. A future
  package adds an FHS migration without editing the reconciler.

Fragment grammar (strict; malformed fails the build):

- `dir <abspath> <mode> <owner> <group>` — ensure corrected
  real directory.
- `replace-symlink-dir <linkpath> <declared-target> <mode>
  <owner> <group>` — replace ONE known historical symlink.
  `<declared-target>` is literal link text, never normalized
  (`../run` is valid; readlink must equal it exactly).
- `rmdir-if-empty <abspath>` / `rmtree-if-empty <abspath>` —
  volatile residue: empty removes, non-empty is left in place
  and reported (never fails an upgrade for a running daemon).
- `rmdir-or-fail <abspath>` / `rmtree-or-fail <abspath>` —
  structurally forbidden residue: non-empty is a loud failure
  requiring manual intervention.

`ensure-fhs` never follows symlinks in any stanza (lstat the
target, inspect parent components without following). `dir` on a
symlink fails unless an exact `replace-symlink-dir` declaration
authorises that historical link. Recursive removals never
traverse a symlink. No stanza creates symlinks, copies, or moves:
PID/socket migration is inexpressible by construction.

Generated install/upgrade callers run `ensure-identity` first
where an accounts.d fragment exists, then `ensure-fhs` — never
the reverse (fresh installs need the identity before chown).
Named non-root owners must resolve deterministically: the same
output's accounts.d declaration or a recognised baselayout base
identity. There is no deinstall/reversal operation: layout never
reverts on `apk del`, and accounts.d disable behaviour is
unchanged. The global `/var/run` symlink swap never runs in a
live post-upgrade: it converges at a safe early-boot point
before ordinary services start (boot-convergence service, both
init systems).

Publish collision is exact-path only: two packages migrating the
same path refuse, while parent/child declarations (baselayout
`/var/run`, mariadb `/var/run/mysqld`) coexist.

## Runtime library placement (FHS non-usrmerged)

Saphira is non-usrmerged: `/bin`, `/sbin`, `/usr/bin`, `/usr/sbin`
are distinct trees and `/lib` is separate from `/usr/lib`.
Shared-library placement follows FHS 3.0:

- A runtime library needed by any binary in `/bin` or `/sbin`
  (DT_NEEDED closure) ships its versioned runtime objects and
  SONAME symlinks in `/lib`. When a library serves both `/bin|/sbin`
  and `/usr/*` consumers, `/lib` wins.
- Libraries needed only by `/usr/bin` or `/usr/sbin` binaries ship
  in `/usr/lib`.
- Move only the runtime chain: versioned objects plus SONAME links
  (e.g. `/lib/libncursesw.so.6`, `/lib/libncursesw.so.6.5`). The
  development linker name stays in `/usr/lib` and points back
  (e.g. `/usr/lib/libncursesw.so` -> `../../lib/libncursesw.so.6`);
  pkg-config data stays in `/usr/lib/pkgconfig`. Precedent:
  `/recipes/acl/recipe.sh` (builds to `/usr/lib`, moves `.so.1*`
  to `/lib`, symlinks `.so` back).
- Pinned `/lib` residents (never move out): the musl loader and
  libc (`/lib/ld-musl-*`, `--syslibdir=/lib`; every binary's
  PT_INTERP), openrc `librc`/`libeinfo` (`--libdir=/lib`), `acl`
  `libacl.so.1*`, `shadow` `libsubid.so.5*`.
- Same-package path moves (`/usr/lib` -> `/lib`) need no
  `replaces=`; unowned fossils at the destination path must be
  removed before the corrected revision installs, otherwise apk
  collides with files it does not own.
- `/lib64` and `/usr/lib64` are forbidden in seeds and payloads;
  `buildpkg` enforces this.

## Configure layout baseline (prefix/sysconfdir/localstatedir)

For genuine GNU/Autoconf-style configure recipes, Saphira's explicit
baseline is:

- `--prefix=/usr`
- `--sysconfdir=/etc`
- `--localstatedir=/var`

These must not be inherited from upstream defaults: autoconf derives
`sysconfdir` as `$prefix/etc` and `localstatedir` as `$prefix/var`, so a
missing flag silently publishes `usr/etc` or `usr/var` payload paths
(proftpd compiled `PR_RUN_DIR=/usr/var`; lynx installed to `/usr/etc`).
This is packaging intent, not cosmetic consistency.

`--runstatedir` is deliberately NOT mass-added: with
`--localstatedir=/var`, normal Autoconf inheritance yields `/var/run`,
which is valid under Saphira's deliberate `/run` vs `/var/run` split.
Set it explicitly only where upstream supports it AND the package has a
deliberate runtime-location requirement.

Custom/non-Autoconf recipes (custom configure scripts, waf wrappers,
cabal `Setup.hs configure`, make-only builds, bootstrap scratch
prefixes) MUST NOT be forced onto GNU dir flags - some reject unknown
options fatally (fio, talloc). They carry a documented
`# layout-exception:` comment instead. Flags are acceptable on a custom
configure only where silently accepted or natively supported (musl
ignores `VAR=*` silently; dhcpcd implements `--localstatedir`
natively). The static gate understands this distinction: a recipe
invoking configure must pass all three flags or document its exception.

Payload backstop: `makepkg` refuses any file or directory beneath
`usr/etc`, `usr/var` or `usr/com` unless covered by an explicit
reviewed `LAYOUT_ALLOW` entry (owner-bound, exact paths; ancestor dirs
implicitly covered). Default state is refusal.

## Toolchain dependencies
A compiler is self-contained: main `gcc` ships the compiler drivers,
assembler integration, CRT objects, static libgcc and all headers.
There is no `gcc-dev` split (retired; `gcc` replaces it). Runtime-only
systems keep `gcc-libs` without a compiler - never fold runtime
libraries into the compiler package.

- A recipe that compiles C or C++ lists `gcc` in makedepends.
  Nothing else is needed for the compiler itself.
- Genuinely optional development interfaces keep their `-dev` splits
  (`openssl-dev`, `zlib-dev`, ...): list exactly what is consumed.
- `binutils` and `make` lines stay as written (explicit toolchain
  closure). `musl` libc headers come from the base root implicitly;
  kernel UAPI headers are pinned explicitly (`saphira-kernel-headers`)
  where consumed.

## Source contract (vendor=)
Upstream archives are vendored in the local recipe collection: each
fetchable recipe pins what it consumes AND carries the bytes.

- Single-source recipes declare `vendor=<url>` plus `sha256=<64-hex>`
  (`source=` is the older spelling; either one without the other is a
  recipe error, refused by resolvepkg and buildpkg-single), and store the
  verified archive as `files/<url-basename>` with a `files/<basename>.sha256`
  sidecar. `fetch-vendor-sources` fetches/verifies/vendors every pair;
  `recipe-rules.sh` fails closed on any missing archive.
- At build time the vendored archive always wins: buildpkg-single verifies
  `files/<basename>` against sha256= and never re-downloads it. Unvendored
  recipes fall back to the content-addressed cache at `SAPHIRA_SOURCE_CACHE`
  (`/var/cache/saphira/sources`), then to a verified download.
- Converted recipes read the archive as `$RECIPE_DIR/files/<name>` when present,
  `$SOURCE_ARCHIVE` otherwise, and fail closed when neither
  exists. Wheels are consumed as files (`$SOURCE_ARCHIVE`), not sources.
- Multi-version recipes (gcc, saphira-kernel) select per-version
  vendor=/sha256= pairs in a `case` on the env-selected version
  (`SAPHIRA_GCC_VERSION`, `SAPHIRA_KERNEL_VERSION`); unknown versions
  fail closed. URL basename must equal the consumed archive.
- Multi-source recipes (nginx: main tarball plus module tarballs) stay
  legacy until a multi-fetch extension lands; convert only what the
  single-source path can carry. `audit-vendor-sources` surveys readiness.
- Never invent a URL: basename, bytes (sha256), reachability, and a
  sourceless build are verified per recipe before conversion.

## Feature policy for ports

The `/reference-package-recipes` recipes are historical bootstrap references
(SDK/stage0/stage1/stage2/stage3/stage3image/stage4/stage4packages). They
were intentionally conservative. Do NOT treat their disabled/minimal feature
set as the desired native Saphira configuration.

- Inspect the current `/recipes` tree and the current native APKs in
  `/out/stage4/packages/x86_64` first. If an r1-or-newer native APK provides
  a dependency capable of enabling a feature, ENABLE that feature.
- Never deliberately disable a feature merely to make a port easier when the
  dependency exists in the native package universe.
- Old r0 Stage4 APKs are historical evidence of capability, never build
  closure inputs.
- If a desired feature needs a missing native dependency, report
  `PACKAGE -> BLOCKED_BY_<dependency>` and port that dependency first.
  Do not solve it with `--disable-foo` / `-DWITH_FOO=OFF` unless the
  operator explicitly removes the feature.
- Prefer explicit enable/disable switches over silent autodetection.
- After building, verify the intended features actually shipped (configure
  summary, pkg-config, `--version`/features output, linkage, plugins).
- `foo-dev` in an old recipe maps to whatever the current recipe actually
  provides (often the main package). Never recreate a split just to keep an
  old name.
- Toolchain guardrails: `gcc-no-gcc-branch-cost` is obsolete (branch-cost
  policy lives in `/recipes/gcc`); do NOT rebuild GCC 12.1/13.2 or musl-libc
  as part of migrations. If a port seems to require that, STOP and report.

## Feature policy authority

The Saphira author decides feature policy.

Agents must not classify supported upstream features as niche,
unnecessary, unwanted, optional, excessive, or out-of-scope on the
author's behalf.

Preserve upstream capability by default.

A capability may be omitted only when:
- explicitly decided by the author, or
- blocked by a concrete technical, security, licensing, architectural,
  or unavailable-dependency reason.

Every --disable-* / --without-* requires an explicit documented reason.

"Not installed by default" does NOT mean "unimportant" or "unsupported".

Perl is the concrete precedent:
it may not be in every base installation, but it is essential supported
Saphira infrastructure because software such as ldirectord depends on it.

## logrotate.d fragments (first-class convention, mirrors accounts.d)

If the recipe creates or configures persistent file logging, it owns
a rotation fragment — unless rotation is explicitly handled
elsewhere (the service logs only to journald, only to syslog, or the
logger itself owns its outputs, e.g. syslog-ng, sysstat/sa):

- Fragment lives at `files/logrotate.d/<name>` (name it after the
  package or service) and installs to `/etc/logrotate.d/<name>`
  (`install -D -m 0644`, same idiom as accounts.d fragments).
- The owning recipe knows the reload semantics, so it declares them:
  daemon reopen/signal where supported, copytruncate otherwise.
- Every stanza carries `missingok`: the fragment activates whenever
  logrotate is installed, possibly before the service ever writes.
- Never reference `/var/log/journal` (journald retention owns that);
  never invent `/var/log/messages`-style files no logger writes.
- Do NOT add a `depends` on logrotate: the fragment is inert without
  it, and installing the package must never drag logrotate into
  minimal systems.

Ownership is single: one package owns each `/etc/logrotate.d/<name>`
(the publish gate fails dual-owned paths). `logrotate` itself ships
only the master config, scheduling, and genuinely ownerless generics.
`logrotate-fragments.sh` enforces the mapping statically.

## Provenance discipline

- Recipes pin `source=` URLs and verify `sha256`; local payloads come from
  `files/`, never from invented upstream archives.
- Published revisions are preserved: different bytes require a new `pkgrel`.
  Same-name-same-version replacements must out-rank stage4-era r0 artifacts
  explicitly (e.g. `>=N-r1` constraints) — resolution is repository-first.
- Do not depend, directly or transitively, on `akadata-base-abi` (retired
  marker; its recipe is disabled). The base ABI marker is `saphira-base-abi`.
- Every recipe change is a git commit (`area: lowercase summary`) with the
  commit hash and rationale recorded in project memory afterwards.

## Retention policy (hatched live view)

- r0 is historical only. `hatchling` may retain historical r0 APKs
  forever as archive/history; `hatched` must not contain r0 at all:
  `pkgrel == 0` is permanently deprecated in the live view,
  `pkgrel >= 1` always supersedes r0 within its lineage (pkgrel is only
  meaningful within its package/version lineage - no generic
  cross-lineage version comparison is ever invented for this).
- A published r0 claim is history, never an active claim: r0 is never a
  retention or rollback candidate, never preserved by a dependency or
  explicit hold, never an active file-ownership or Unix-identity
  claimant, and never wins package selection or collision arbitration.
  The archive contains history; it is not the live ownership universe.
- Prune order on every live publication: (1) every published r0 retires
  unconditionally; (2) normal retention over r1+ (latest keep
  generations, exact live dependency holds, explicit holds); (3) split
  siblings retire atomically in the same pass; (4) indexes/identities
  regenerate; (5) `repository.db`/claims update in the same
  transactional publication flow. An explicit hold naming an r0 is
  rejected loudly; a live package exactly depending on an r0 NVR is a
  broken live dependency and fails closed with the dependent named (the
  consumer recipe must be fixed/rebuilt at r1+ - the r0 is never kept
  to satisfy it). Retirement goes through the transaction only, so
  files, indexes, identities, rows and claims stay coherent - never
  delete r0 APKs from hatched by hand.
- The live generation otherwise keeps the newest
  `SAPHIRA_RETAIN_GENERATIONS` NVRs per package name (default 2). Older
  NVRs retire inside the signer's publication transaction: files go
  before index regen, rows go with the staged apply in one
  `BEGIN IMMEDIATE`/`COMMIT` - never bare `rm`, never one-by-one
  (split siblings retire together or not at all).
- An older r1+ NVR survives only for an exact live dependency (a
  constraint no kept NVR satisfies but it does) or an explicit
  `SAPHIRA_RETAIN_NVR` hold. Archive generations are never pruned.
- `hatchling` is the permanent archive: nothing is ever deleted there.

## Installed filesystem hygiene

- No installed APK may contain an absolute symlink whose target is under
  `/build` (constructor workspace: worker roots, staged sources, package
  tmp). `makepkg` refuses such payloads at construction, naming package +
  symlink + target. Upstream install rules that bake absolute build paths
  (kernel `modules_install`, bzip2 helpers) must be rewritten post-install
  to packaged locations. Relative links are unaffected.

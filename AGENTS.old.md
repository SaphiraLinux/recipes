# Saphira Linux recipes

Native Saphira package recipes built by Egg: the running Saphira v0.1 controller whose
job is to hatch self-hosting Saphira v0.2. `README.md` is the canonical contract document.

## Session protocol (MCP memory servers)


You have access to `s25-messenger`. It is a pure bearer-based MCP/tool surface.

This task is intentionally testing the tool surfaces together.

TARGET
www.breathtechnology.co.uk

RULES
- Do NOT use filesystem access for this review.
- Do NOT read the local website source tree.
- Do NOT use shell/file inspection as a substitute for MCP/tool discovery.
- Review the live/public website and the MCP/tool surfaces available to you.

SKILLS
- Inspect the available Skills first.
- Identify which Skills are relevant to this website/project.
- Use relevant Skills where they materially improve the review.
- Do not invoke unrelated Skills merely because they exist.

GOVERNANCE
- Inspect the available governance Skills/capabilities.
- Decide which governance controls meaningfully apply to
  `www.breathtechnology.co.uk`.
- Apply the relevant governance checks.
- Explain why each applied governance check is relevant.
- Do not force governance controls onto areas they do not cover.

POCKET / S25
- Use `s25-messenger` where its bearer-based tools are relevant.
- Exercise the actual bearer/MCP route rather than recreating the same work
  locally.

UNIFIED MCP
- Unified MCP is the persistent project memory/control surface.
- You may update it throughout the task using its bearer endpoints.
- Record useful observations as they occur, not only at the end.
- Use the appropriate Unified MCP objects for:
  - logs
  - tasks
  - findings/intel
  - decisions
  - evidence/provenance
  - unresolved issues
- Do not duplicate meaningless status noise.

REVIEW
- Inspect the website as it exists now.
- Use evidence from the available tools.
- Separate:
  - observed fact
  - inferred issue
  - recommendation
- Do not fabricate a finding because a tool or Skill expects one.
- If a check cannot be completed through the permitted surfaces, say so.

OUTPUT
Report:
1. which Skills were available and which you actually used;
2. which governance capabilities were relevant and applied;
3. which Pocket/s25-messenger tools were exercised;
4. what was persisted to Unified MCP;
5. findings about the website, with evidence;
6. anything the permitted tool surfaces could not establish.


; please stop here and initialise the mcp and discover tools, 

once you have ; taken onboard what you learned here then prepare to copy AGENTS.md AGENTS.old.md; 

And read below and concider a consise way that help you reconnect to the mcp tools after discovery? 

Durable cross-session state lives in MCP memory, not scratch files. All sqlite-memory
servers share one database (reached via host `homer`).

- Session start: `session_session_recall` (+ `session_resume_context` when resuming),
  then reconcile against current `git log` before acting.
- Search memory BEFORE reconstructing prior work from filesystems:
  `memory_search_nodes`, `tasks_find_by_title`, `session_search_by_project`.
  Do not re-derive what is already recorded.
- After a verified real change: Git commit FIRST, then `memory_add_observations`
  recording the commit hash, what changed, what triggered it, and why.
- Mid-work checkpoints: `tasks_upsert_note_by_title_project` (idempotent) plus
  `session_session_save`, so the next session resumes cleanly.
- Supporting surfaces when needed: `entity_*` (task-entity links, overlap/merge),
  `intel_audit_memory` (ledger drift/duplication), `bridge_*` (cross-machine sync only),
  sequential-thinking (complex multi-step diagnosis).

## codex.history.md

Temporary takeover material, not a permanent record. If present: read it to recover
exactly where work stopped and any reasoning not yet in memory; reconcile with Git and
MCP memory; absorb anything unique into memory or task notes. Once absorbed and nothing
unique remains, delete it. Nothing else may depend on its existence.

## Recipe source precedence

When creating or porting a recipe, use the first basis that exists:

1. Existing current `/recipes` recipe.
2. Known-working Saphira v0 recipe in `/reference-package-recipes`.
3. `/cports` for upstream/current guidance.
4. Upstream project sources/documentation when necessary.

- `/reference-package-recipes` is the complete known-working v0 bootstrap catalogue that
  produced the existing package universe. Read-only; never edited or built directly;
  normally the first basis for ports where a package exists there. Preserve proven
  Saphira-specific build decisions.
- When adapting, remove old staged-builder disable/skip machinery (the native builder
  scopes work via dependency resolution and explicit targets), but do NOT blindly strip
  legitimate package configure flags such as `--disable-static`.
- Port into `/recipes` adapted to the native v0.2 recipe contract rather than modifying
  reference copies.
- `/cports` is read-only guidance (dependency hints, patches, configure options,
  subpackage structure, newer package knowledge). It must not override deliberate
  Saphira filesystem, musl, non-usrmerged, init, or packaging policy.

## What Egg is (generation handover)

Egg is not a clean package-only installation. It is the running Saphira v0.1 musl-libc
OS produced by the historical Stage3/Stage4 bootstrap, which installed many files and
build tools directly into the image before APK ownership became authoritative.

Diagnosing Egg itself:

- `/etc/apk/world` is NOT a complete inventory of what exists on Egg.
- `apk info -W FILE` returning no owner does not mean the file is absent or invalid;
  it may be historical bootstrap-installed content.
- Egg deliberately contains historical Stage3/Stage4-installed content that may not
  appear in APK world or ownership data. This is expected generation-zero state, not
  evidence of corruption. Inspect the filesystem and command availability alongside
  APK metadata; never infer "missing" from APK state alone.

However, historical availability must not leak implicitly into v0.2 builds:

```
historical Stage3/Stage4 bootstrap
        |
Saphira v0.1 Egg (controller host)
        |
native package builder (rootless)
        |-- trusted existing APK repository (the sole seed source)
        +-- native /recipes dependency closure
        |
clean Saphira v0.2 root/package universe
        |
v0.2 becomes capable of rebuilding itself
```

Keep these boundaries distinct:

1. Egg host environment — the real running v0.1 OS; may contain useful unowned
   historical bootstrap files/tools. Nothing is copied from it into build roots.
2. APK-managed clean-root seed — the full foundation including the C library,
   headers and toolchain runtimes (`musl`, `musl-dev`, `saphira-kernel-headers`,
   `libxcrypt`, `flex`), installed into the clean root from the trusted
   repository as named packages (`SAPHIRA_BUILD_SEED`). Package names are the
   boundary; no host file ever crosses.
3. Recipe dependency closure — dependencies satisfied repository-first, or built from
   `/recipes` where necessary.
4. Final v0.2 system — progressively eliminates reliance on unowned Stage3/Stage4
   residue until it can rebuild itself.

Historical files discovered on Egg are evidence about how v0.1 was built, never
build inputs. Non-foundational items should normally be traced
to the package that ought to provide them and moved into proper APK ownership as v0.2
develops.

Objective: Saphira v0.1 builds Saphira v0.2, then v0.2 builds Saphira itself.
The Egg hatches.

## Rootless build rules

- Normal operation: `buildpkg PACKAGE`. Closure resolution is repository-first:
  satisfying trusted APKs are reused; dependencies are never rebuilt or upgraded merely
  because a newer recipe exists. An explicit top-level request always builds the current
  native recipe.
- No sudo/root anywhere in the build path (tests assert sudo fails).
- `installpkg` (live-system install) and `sign-apk-repo` (signing/publication) are the
  ONLY privileged admin boundaries. `makepkg` is the sole APK constructor.
- `install-saphira-packager` is the explicit bootstrap/admin chicken-and-egg exception:
  an administrator may run it to install or refresh the controller before
  `saphira-packager.apk` exists. It is never part of `buildpkg`, never installs recipe
  dependencies, and never publishes.
- Administrative tool layout: all controller tools — including `sign-apk-repo` — are
  installed under `/usr/bin` and are owned by `saphira-packager`. Privilege comes from
  how a tool is invoked (sudo for `installpkg`/`sign-apk-repo`), never from where it
  is installed.

## Workspaces and failure lifecycle

- One visible workspace per top-level build: `/build/PACKAGE.buildpkg`, holding one
  evolving disposable root as an OverlayFS merged view (`root/`): one canonical
  immutable base root at `/build/rootfs_overlay/base` (fingerprint-state in
  `/build/rootfs_overlay/state/`) plus per-workspace `upper/` and `work/` layers.
  Package dependencies install only into that merged root. `buildpkg` is
  authoritative: a requested build produces the current recipe NVR or fails for
  a genuine build error. The base rebuilds automatically when the live seed
  NVRs drift from its receipt (a bumped seed package must never build against
  an obsolete base), and clean roots carry a complete minimal account database
  (passwd+group+shadow) for package install scripts. No manual base rebuild,
  cleanpkg, or operator knowledge is part of the normal `buildpkg` path.
- `/build` is scratch space, but failed `PACKAGE.buildpkg` workspaces are retained
  diagnostic evidence, not disposable until handled through the trusted lifecycle:
  a failed run writes marker content `saphira-buildpkg-failed/v1`; retry requires that
  exact marker; unmarked workspace collisions are refused. A retained workspace
  whose base generation is stale (the canonical base was rebuilt since it ran)
  is never reused for execution: it moves aside to
  `PACKAGE.buildpkg.stale-<timestamp>` with logs intact while a fresh workspace
  builds from the current base. Same-generation retries keep the marker
  lifecycle. Never delete, bless, or overwrite an unmarked workspace — use
  `cleanpkg` or move it aside visibly for diagnosis.

## Bootstrap inputs (one thing, not two)

- The repository build seed: APK-managed packages installed into the clean root
  from the trusted repository, configured as named packages (`SAPHIRA_BUILD_SEED`
  in `saphira-packager/files/package_builder.sh`). The seed carries the whole
  foundation — C library, headers, toolchain runtimes — so no host file ever
  crosses into a build root. There is no pathname manifest and no second
  filesystem-level dependency database alongside APK.

Root initialization (`/bin/sh -> bash`, CA bundle, resolv.conf/hosts bind-ins) happens
explicitly inside the namespace via controller code/config — never copied ad-hoc from
Egg.

## Filesystem layout policy

The durable rule is the clean `/lib` + `/usr/lib` layout: `/lib64` and `/usr/lib64`
are forbidden in seeds and payloads (`makepkg` enforces this on every payload
path and symlink target; `buildpkg` performs no payload validation of its own).
The current target architecture is x86-64 — a per-generation choice, not an
eternal architectural restriction. `RECIPE_RULES.md` carries the normative
non-usrmerged, dual-init and headless policies.

## GCC toolchain policy

Saphira carries the AKADATA backport of GCC commit
52cd02606b906160bf47001a00b446c35d46f15f:

    x86: Increase generic tune branch misprediction cost

gcc/config/i386/x86-tune-costs.h:

    COSTS_N_INSNS (2)
          ->
    COSTS_N_INSNS (2) + 3

This is intentional Saphira compiler policy inherited from the bootstrap,
not disposable Stage0 scaffolding.

When GCC is ported/upgraded:

- preserve the semantic change;
- verify the patch against the new source;
- do not silently drop it because upstream code moved;
- `/cports` is guidance and does not override this Saphira-specific policy;
- record any deliberate removal/change as an explicit reviewed toolchain decision
  (memory observation referencing the decision commit).

Use the complete working Saphira bootstrap toolchain to build/package the
native GCC generation during v0.1 -> v0.2. Do not fall back to older GCC
bootstrap chains (e.g., for GNAT/GDC) while that toolchain is available.

## Recipe format

- `<package>/recipe.sh` requires the metadata appropriate to the package.
- Recipes downloading upstream source must pin the `source` URL and verify it with
  `sha256`, AND vendor the verified archive as `files/<url-basename>` with a
  `files/<basename>.sha256` sidecar (`<sha>  <basename>`). New fetches go
  straight to `files/` via `fetch-vendor-sources` — never `/tmp`, never
  anywhere else. The public mirror excludes archives; public builders fetch
  via URLs.
- Local/meta/controller recipes whose payload comes from files in the recipe tree do
  not invent an upstream source/archive merely to satisfy this rule.
- `depends` / `makedepends` accept version operators (`=`, `>=`, ...); `subpackages`
  declares split outputs; `-dev` / `-doc` names resolve to the base recipe.
- The worker provides `PKGDEST` (staging), `SRC` (extracted source), `BUILDDIR`;
  recipes define `recipe_build()` and `recipe_install()`.
- A recipe may declare `disabled=yes` with `disabled_reason='...'`; the builder
  then skips it (scan reports and skips, buildpkg refuses, resolvepkg fails closed
  if a dependency would resolve from it).
- `repo=` is a validated-but-INERT metadata field. It is a historical component
  label from the generation-zero akadata universe (`main` vs `saphira`); the native
  builder has a single flat per-arch repository (`SAPHIRA_REPO_DIR/$arch` ->
  Packages.adb/APKINDEX -> packages.saphira.vm2.uk/hatchling), and no tool reads
  `repo=` for sorting, dependency resolution, output placement, indexing, signing,
  or publication - it never even reaches `apk mkpkg` metadata. The mixed
  `repo=main` / `repo=saphira` values across recipes are therefore harmless and
  are deliberately left un-normalised; do not "migrate" them without first
  introducing real component semantics (a per-component repository split) into
  the builder toolchain. Only its non-empty presence is enforced.

## Verification

No CI exists. Run affected suites locally before every commit, plus `git diff --check`:

    python3 -m py_compile saphira-packager/files/buildpkg \
        saphira-packager/files/resolvepkg saphira-packager/files/makepkg
    saphira-packager/tests/resolvepkg.sh saphira-packager/files/resolvepkg
    saphira-packager/tests/makepkg.sh saphira-packager/files/makepkg
    saphira-packager/tests/kernel-layout.sh saphira-kernel/files/install-kernel-layout.sh
    saphira-packager/tests/kernel-release-size.sh $(ls -1 /out/stage4/packages/hatched/x86_64/saphira-kernel-*.apk | head -1)
    saphira-packager/tests/kernel-module-strip.sh $(ls -1 /out/stage4/packages/hatched/x86_64/saphira-kernel-*.apk | head -1)
    saphira-packager/tests/accounts.sh
    saphira-packager/tests/recipe-rules.sh
    saphira-packager/tests/recipe-coverage.sh
    saphira-packager/tests/crypt-ownership.sh
    saphira-packager/tests/subordinate-ids.sh
    saphira-packager/tests/bpf-userns.sh
    sh saphira-initramfs-tools/tests/initramfs.sh
    sudo saphira-install-tools/tests/chroot-bind.sh saphira-install-tools/files/saphira-chroot
    saphira-packager/tests/cleanpkg.sh saphira-packager/files/cleanpkg
    saphira-packager/tests/publication.sh saphira-packager/files/sign-apk-repo \
        saphira-packager/files/makepkg saphira-packager/files/checkpkg
    saphira-packager/tests/repo-state.sh saphira-packager/files/sign-apk-repo \
        saphira-packager/files/saphira-repo-migrate saphira-packager/files/saphira-repo-state \
        saphira-packager/files/makepkg
    saphira-packager/tests/seed-repo.sh saphira-packager/files/seed-repo \
        saphira-packager/files/sign-apk-repo saphira-packager/files/makepkg
    saphira-packager/tests/promote-repo.sh saphira-packager/files/promote-repo \
        saphira-packager/files/makepkg saphira-packager/files/sign-apk-repo
    saphira-packager/tests/clean-build.sh saphira-packager/files/buildpkg
    saphira-packager/tests/closure-local-deps.sh saphira-packager/files/buildpkg
    saphira-packager/tests/buildpkg-unprivileged.sh saphira-packager/files/buildpkg-single
    saphira-packager/tests/buildpkg-staged-input.sh saphira-packager/files/buildpkg-single
    sudo saphira-packager/tests/kmod-provenance.sh saphira-kernel/files/stage-kmod-input.sh
    saphira-packager/tests/saphira-build.sh
Prerequisites: bwrap, apk, python3, rootless user namespaces, network
(resolv.conf/hosts). Suites are self-contained under hermetic dirs in
`SAPHIRA_TMPDIR` and assert
Egg's package DB/world remain unchanged.

One suite is deliberately privileged and is invoked with `sudo` above:
`saphira-install-tools/tests/chroot-bind.sh`. It proves mount behaviour in
`saphira-chroot --bind`/`--bind-ro`, which cannot be observed without the
ability to mount. It is kept out of the rootless set on purpose -- the
rootless property is itself an invariant for the package build path -- and it
confines its mounts to its own temporary tree inside a private mount
namespace, so it neither requires nor exercises privilege anywhere else. It
never elevates itself: run without root it says so and stops.

## Public-distribution size policy

saphira-kernel is a public package and its size is a release gate, not a
build artefact. r7 grew 32 MiB -> 600 MiB compressed and ~70 MiB -> ~2.4 GiB
installed over three revisions, from two independent causes: `d2e581d` shipped
the prepared module build tree as runtime payload (+1648 MiB), and `8056167`
enabled `CONFIG_DEBUG_INFO_BTF`, from which `olddefconfig` DERIVES
`CONFIG_DEBUG_INFO_BTF_MODULES=y` and so put a DWARF database in all 218
modules (+704 MiB). A derived Kconfig setting appears in no file a reviewer
reads, and no build log, module count or `/boot` change showed it. Only a size
comparison did.

So two guards run as release checks, and both are proven against the retained
bad artefact `saphira-kernel-7.2.2-r7.apk`, which stays in the repository
permanently as evidence:

  - `kernel-release-size.sh` fails if the payload contains any `/usr/src`
    entry, any `modules` build/source pointer, an `installed-size` above 2x the
    r5 baseline (73,289,642 B), a `/lib/modules` over 150 MiB, or a module
    count below 200.
  - `kernel-module-strip.sh` installs the package and fails if ANY runtime
    `.ko` carries a `.debug_*` or `.BTF` section, or if the largest module
    exceeds 20 MiB.

The baseline is r5, the last known-good public packaging. Raising the ceiling
is a reviewed decision made in the open in `kernel-release-size.sh`, never a
side effect of a build.

r7/r8/r9 are retained intentionally and permanently as historical release
artefacts. Saphira does not delete or alter released signed packages to hide a
mistake; the regression stays auditable rather than merely confessed.

## Crypt namespace ownership

musl owns the generic crypt namespace, deliberately. musl provides
`crypt()`/`crypt_r()` inside libc and ships an **empty** `libcrypt.a` so
build systems that hardcode `-lcrypt` still link; generic `-lcrypt`
therefore resolves `crypt()` out of libc, by design. `libxcrypt-dev`
supplies that empty archive and must never install a generic
`libcrypt.so` or a *real* generic `libcrypt.a` — `-lcrypt` falls back to
the `.a`, so a real one would be silently selected and hand every consumer
the heavy hashes without anyone asking. What libxcrypt offers instead is
`libxcrypt.so` plus `pkg-config libxcrypt`, so selecting the extended API
is explicit. `saphira-packager/tests/crypt-ownership.sh` proves all of
this against reconstructed real packages, and the recipes assert the same
invariants at build time so a bad package is refused before publication
rather than after.

## pkgrel discipline

No r0 packages, ever. Every recipe ships `pkgrel>=1`; the initial
publication of a package is r1. resolvepkg refuses to plan and
buildpkg-single refuses to stage any recipe at pkgrel 0, sign-apk-repo
refuses any staged r0 in a multi-generation run, and no r0 package
is allowed in the live generation repository (hatched); historical r0
artifacts stay in hatchling only. pkgrel exists for consumers: bump it when
a payload change must reach the repository (immutable filename rule), never
as a bug counter. While new orchestration tooling settles, a handful of
quick bumps (r4->r5->r6) is healthy; each must fix a concrete, proven
defect. Fixes that have not yet proven themselves batch into the next
rebuild. saphira-build warns when a package requeues repeatedly in a short
window - that is the r55555 smell.

## Change discipline

- Diagnose from retained workspace logs and `plan.json` before changing builder code;
  address coherent root causes only; no redesign without evidence.
- Commits: `area: lowercase summary` (e.g. `packager: require exact failed marker for
  retries`). Commit only after suites pass; then record in memory per the session
  protocol above.

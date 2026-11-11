# musl patches

This file lives beside the patch files it documents
(`saphira-baselayout` convention: `PATCHES.md` sits in the same
directory as the patches). Every patch below states **why it exists**,
whether upstream can take it, and what breaks if it is dropped. A
patch with no documented reason is a defect in this file, not a
mystery for the next reader.

| File | Why | Upstreamable? |
|---|---|---|
| `0001-default-pthread-stack-1MiB.patch` | Default pthread stack 128 KiB → 1 MiB. musl's tiny default starves real-world threaded code (rust, go runtimes, browsers); Saphira ships a general-purpose userland, not a minimal libc demo. Drop it and threaded programs die with stack overflow under load. | No — deliberate Saphira policy, like the gcc branch-cost backport. |
| `0002-netinet-in6-kernel-uapi-coordination.patch` | Guard `struct in6_addr` etc. with `#if !defined(_LINUX_IN6_H)` so musl headers interoperate when kernel UAPI headers were included first (same coordination glibc does via `__USE_KERNEL_IPV6_DEFS`; layouts are compatible per `linux/libc-compat.h`). Drop it and any TU including `<linux/in6.h>` before `<netinet/in.h>` fails to compile. | Possibly, as a musl upstream contribution; not submitted. |
| `0003-utmp-wtmp-real-paths.patch` | Point `_PATH_UTMP`/`_PATH_WTMP` (and therefore `UTMP_FILE`/`WTMP_FILE`, which expand from them) at the real databases `/var/run/utmp` and `/var/log/wtmp` in **both** `paths.h` and `utmp.h`. Upstream musl deliberately neuters these to `/dev/null/*`. On Saphira the databases are real: login accounting (`last`, `lastlog`, sshd session recording) depends on them. Proven 2026-10-23: patching `paths.h` alone was insufficient — openssh `defines.h` prefers whichever `_PATH_*` macro it sees and `utmp.h` still said `/dev/null`, so the r4 sshd wrote `/dev/null/wtmp` despite correct `CONF_*` overrides (which are dead whenever libc defines the macros). The header is the single source of truth. Headers only, no code, no ABI. | No — contradicts upstream's intentional neutering. |

All three patches are verified by hash pins in `recipe.sh`
(`musl_patch_sha256`, `in6_patch_sha256`, `utmp_patch_sha256`): editing
a patch file without refreshing its pin fails the build visibly.

## Upstream corrective backports (`0101`–`0170`, minus deferred `0130`)

Ordered backport series from upstream `v1.2.6..master` (HEAD
`7813e911`, 2026-10-14): 73 upstream commits reviewed, 69 carried
here, 4 deferred (`fallocate` flags, `__WORDSIZE` removal, fmaf
rewrite, `reclen_t` — enhancements or needing wider review, none
corrective for Saphira). Every file is a `git format-patch`
rendering: the `From:` line carries the full upstream hash, author
and date. Order is topological (= filename order) and required:
the scandir, clock_nanosleep and wordexp units apply as stacked
pairs/chains. Pinned by `UPSTREAM-SHA256SUMS`, applied by the
`recipe.sh` loop in glob order, verified with the static-PIE
`libc.a` policy intact. Per-patch subject, files, category,
prerequisite and test evidence live in `AUDIT-SERIES.md`; the full
review, test evidence, arch and cross-toolchain implications live
in `AUDIT-REPORT.md` and `AUDIT-FINAL-REVIEW.md`; the focused
regression tests live in `audit-tests/`. The series changes no
exported symbols (1650/1650 identical) and no public header besides
the documented `CPU_ISSET` tightening; behaviour changes are all
bug→fix direction.

## Saphira arch optimisations (`0004` + `0008`–`0012` + `0014`)

Validated x86_64 assembly fast paths, replayed onto the r7 RC-69 base
from the `1.2.6_p1` experiment lineage (source: `exp/musl-f8-strstr`
@`93f0d39b`; `0004` via `exp/musl-r8` lineage @`d465def8`; files
byte-identical, pins verified). Applied after the RC-69 loop; the
file sets are disjoint from RC-69, and `0011` modifies the `0004`
files so order matters. Drop the `recipe.sh` block to restore pure
r7 behaviour. Pinned by per-patch sha256 in `recipe.sh` like the
policy patches.

| File | Why | Upstreamable? |
|---|---|---|
| `0004-x86_64-rint-roundsd.patch` | `rint`/`rintf` via SSE4.1 `roundsd`/`roundss` following the MXCSR mode (base technique; prerequisite for `0011`). | Possibly, as an arch optimisation; not submitted. |
| `0008/0009/0010-x86_64-{floor,ceil,trunc}-roundsd.patch` | Arch `floor/floorf`, `ceil/ceilf`, `trunc/truncf` (one function per TU): `roundsd`/`roundss` suppress + DAZ-gated cold path, sacrificial `orig+1.0` real op for flag/trap fidelity (DM traps preserved; `ldmxcsr` never traps so it cannot be used). Generic C stays as numerical reference (musl basename override replaces it). | Possibly; not submitted. |
| `0011-x86_64-rint-realop-denormal.patch` | Replaces the `0004` `ldmxcsr` DE-restore with the same real-op mechanism (correct DM-trap behaviour on denormals). | Same as `0004`. |
| `0012-x86_64-nearbyint-roundsd.patch` | Arch `nearbyint`/`nearbyintf`: `roundsd`/`roundss` suppress (`$0x0C`, MXCSR mode) + DAZ-gated cold path with `ucomisd` DE-only restoration; inexact never raised (contract). | Possibly; not submitted. |
| `0014-x86_64-strstr-sse2-short-needle.patch` | Arch 2/3/4-byte needle helpers (`__twobyte/__threebyte/__fourbyte_strstr`, GLOBAL HIDDEN, own TUs, SSE2 only) + `strstr.c` dispatch; generic bodies kept under `#else`, 1B and ≥5B two-way paths untouched. | Possibly; not submitted. |

Deliberately NOT carried: F5 `fmin/fmax` (validated candidate, never
approved), F6 AVX2 `mbsrtowcs` (correct but slower — negative verdict),
F7 `conjf` (unmeasurable — negative verdict), and the `0005`/`0006`/
`0007` experiments (`memmove`/`strncmp`/`memcmp`, test builds only).
Their branches and evidence are preserved untouched.

Validation on this base (see `RECONCILE-VALIDATION.md`): 388224-case
F3 differential (signature-identical to the experiment archive),
97056-case F4 differential (0 fails), 401431-case staged strstr
differential base-vs-cand identical, trap matrices byte-identical to
archive, dynsym 1650/1650 FUNC+OBJECT identical with no new exports, helpers
GLOBAL HIDDEN with direct tail calls, piecheck clean, testsuite
identical to the r2 baseline (5 known failures), loader smoke green,
benches show the documented wins with identical checksums.

# musl patches (1.2.6_p1 sinew lineage, _sinew_version 0.1.0)

1.2.6_p1 supersedes published 1.2.6-r8 (dual identity: musl-compatible
package version for APK, independent Sinew implementation version).
Previous r7 recipe preserved at `musl.disabled/` for reference.
Foundation ball is byte-identical to Saphira musl 1.2.6 (`musl-1.2.6.tar.gz`, sha256
`e9db8b70b0cba3db43b27e84ccd8a0c0958b40029a1c36c9f13817b93787b4d6`,
verified against upstream `v1.2.6`); 0001–0003 + upstream series are
the RC-69 content carried from r7.

| File | Why | Diverges from musl? |
|---|---|---|
| `0001-default-pthread-stack-1MiB.patch` | Inherited Saphira policy: default pthread stack 128 KiB → 1 MiB (guard 8192 unchanged). Drop it and threaded runtimes die under load. | No — identical to musl. |
| `0002-netinet-in6-kernel-uapi-coordination.patch` | Inherited kernel-UAPI guard (`_LINUX_IN6_H` coordination, glibc-compatible layouts). Drop it and TUs including `<linux/in6.h>` before `<netinet/in.h>` fail. | No — identical to musl. |
| `0003-utmp-wtmp-real-paths.patch` | Inherited real `_PATH_UTMP`/`_PATH_WTMP` (`/var/run/utmp`, `/var/log/wtmp` in both `paths.h` and `utmp.h`). Headers only, no ABI. | No — identical to musl. Known carryover: cross-toolchain sysroot omission (musl 0003 defect) is inherited and must be resolved before any sysroot alignment. |
| `0004-x86_64-rint-roundsd.patch` | **r8 delta** (promoted from `exp/musl-r8 @9fd47a9`). Arch `src/math/x86_64/rint.c` + `rintf.c` via SSE4.1 `roundsd`/`roundss` (MXCSR mode) with explicit denormal-operand-bit preservation for subnormal inputs. Generic C stays as numerical reference (musl `REPLACED_OBJS` picks arch files automatically). Evidence: 2.16M-case differential vs generic C 0 fails, 1M-case MPFR value+inexact 0 fails, throughput 1.3–2.3x mixed-input across Egg/route/keeper/minimer/homer, libc-testsuite byte-identical to RC-69, piecheck green; live-swapped on hatchling (SaphiraD) and rebooted healthy. DE=preserve per operator policy. **Superseded in behaviour (not removed) by 0011 on exp branches carrying F3.** | Yes — this is the r8 delta over r7. |

| `0005-x86_64-memmove-sse2-backward.patch` | **EXPERIMENTAL (exp branch only).** Replace the arch backward path (`std; rep movsb; cld`) with SSE2 16-byte blocks (Parker Loflin 31-Oct proposal). Evidence: 564,450 checks x 5 hosts, 0 fails (deterministic matrix + guard pages + 120k fuzz); backward 10-21x, forward/non-overlap 1.00x (identical code path), sorted-insert 9-13x. SSE2 is baseline; no FP state, no ABI change. Forward path untouched (`__memcpy_fwd`). | Yes — first string-routine delta; remove file + recipe block to restore _p1 behaviour. |

| `0006-x86_64-strncmp-sse2.patch` | **EXPERIMENTAL (exp branch only).** Arch `src/string/x86_64/strncmp.s`: page-guarded 16-byte blocks, NUL-aware both sides, unsigned-byte ordering, first-difference decides (600k differential x 5 hosts incl. glibc, 0 fails; guard pages; 4-9x sustained). Drop file + block to revert independently. |
| `0007-x86_64-memcmp-sse2.patch` | **EXPERIMENTAL (exp branch only).** Arch `src/string/x86_64/memcmp.s`: page-guarded 16-byte blocks, pure binary compare (600k differential x 5 hosts, 0 fails; 5-9x sustained). Drop file + block to revert independently. |
| `0008-x86_64-floor-roundsd.patch` | **EXPERIMENTAL (exp branch only, F3).** New arch `src/math/x86_64/floor.s` + `floorf.s` (one function per TU per musl `REPLACED_OBJS` convention; bundling double+float in one TU breaks the shared link with duplicate symbols — proven by failed r3 build, fixed by split): SSE4.1 `roundsd`/`roundss` suppress + DAZ-gated cold path (DAZ=0 arch value; DAZ=1 integer fallback computing the TRUE result in both modes) + sacrificial `orig+1.0` real op for flag/trap fidelity. Musl `REPLACED_OBJS` swaps the generic objects automatically (verified: each arch object defines exactly one `T` symbol, no undefineds; static archive + shared link clean; arch+generic together fail as expected). Evidence: F3 388k differential + trap matrix re-run against split objects, numbers bit-identical to checkpoint 92; sources + harnesses in `musl/tests/f3-work/`. Drop file + block to revert (generic C returns). |
| `0009-x86_64-ceil-roundsd.patch` | **EXPERIMENTAL (exp branch only, F3).** New arch `src/math/x86_64/ceil.s` + `ceilf.s` (one function per TU, same split rationale as 0008): same design (truth: `ceil(+sub)=+1.0`, `ceil(-sub)=-0.0`). Same evidence/revert as 0008. |
| `0010-x86_64-trunc-roundsd.patch` | **EXPERIMENTAL (exp branch only, F3).** New arch `src/math/x86_64/trunc.s` + `truncf.s` (one function per TU, same split rationale as 0008): same design as 0008 (truth: signed zero via DAZ-free integer ops). Same evidence/revert as 0008. |
| `0011-x86_64-rint-realop-denormal.patch` | **EXPERIMENTAL (exp branch only, F3).** Modifies the 0004 `src/math/x86_64/rint.c`+`rintf.c` (applies after 0004): replaces the `ldmxcsr` DE-restore with the same sacrificial real-op mechanism as 0008–0010 (`ldmxcsr` never traps, so it cannot preserve DM-trap behaviour; the real op does). Masked behaviour bit-identical to 0004; unmasked DM/PM trap parity restored. Same evidence as 0008. |
| `0012-x86_64-nearbyint-roundsd.patch` | **EXPERIMENTAL, INTEGRATED (exp/musl-f4-nearbyint only, F4).** New arch `src/math/x86_64/nearbyint.s` + `nearbyintf.s` (one function per TU per `REPLACED_OBJS`): SSE4.1 `roundsd`/`roundss` suppress (`$0x0C`, MXCSR mode) + DAZ-gated cold path; subnormal DAZ=0 flags via sacrificial `ucomisd` (DE only — never PE/UE/IE, FTZ-independent). Masked flags bit-identical to generic; inexact never raised (defining contract). Evidence: F4 97,056-case differential (vfails=0 ffails=0 pefails=0) + trap matrix (DM parity, UM 0/0 parity, PM ref-only documented, IM cand-only sNaN per policy); sources + harnesses in `musl/tests/f4-work/`. Drop file + block to revert (generic wrapper returns). |
| `0014-x86_64-strstr-sse2-short-needle.patch` | **Release candidate r5 (F8).** New arch `src/string/x86_64/twobyte_strstr.s` + `threebyte_strstr.s` + `fourbyte_strstr.s` defining hidden `__twobyte/threebyte/fourbyte_strstr` (GLOBAL HIDDEN: no new dynamic exports, direct tail calls, 0 bad relocs) + `strstr.c` wiring (generic bodies kept verbatim under `#else` for other arches). SSE2 equality-mask 16B windows (overlap step m-1), page-bounded vector loads, scalar tail with the generic fault profile; 1B path and >=5B two-way untouched; O(n) for short-needle paths. Evidence: staged differential 401431/0 (Egg + Minimer N100, guard pages, cross-page matches), staged bench wins (2B absent 8.6x/6.2x, 3B 5.2x/4.9x, 4B 4.5x/3.7x Egg/Minimer; controls tie incl. ADV/PERIODIC), dynamic loader smoke correct, libc-testsuite identical (5 known failures only), net +695B text; sources + harnesses in `musl/tests/f8-work/`. Drop file + block to revert (generic strstr returns). |

All pins verified by `recipe.sh`
(`musl_ball_sha256`, `musl_stack_sha256`, `in6_patch_sha256`,
`utmp_patch_sha256`, `rint_patch_sha256`, `memmove_patch_sha256`,
`strncmp_patch_sha256`, `memcmp_patch_sha256`, `floor_patch_sha256`,
`ceil_patch_sha256`, `trunc_patch_sha256`,
`rint_realop_patch_sha256`, `nearbyint_patch_sha256`,
`strstr_sse2_patch_sha256`): editing a patch
without refreshing its pin fails the build visibly.

## Upstream corrective backports (`0101`–`0170`, minus deferred `0130`)

Independent copy of the musl r7 RC-69 series (69 files, pinned by
`files/UPSTREAM-SHA256SUMS`, applied in glob/topological order).
Upstream HEAD `7813e911` (2026-10-14); 73 commits reviewed, 69
carried, 4 deferred (fallocate flags, `__WORDSIZE`, fmaf rewrite,
`reclen_t`). `From:` lines carry full upstream hash/author/date.
No exported-symbol change (1650/1650), no public-header change
besides documented `CPU_ISSET` tightening. Full rationale in
musl `AUDIT-SERIES.md` / `AUDIT-REPORT.md` / `AUDIT-FINAL-REVIEW.md`
(checkpoint 61); not duplicated here — Sinew tracks musl's audit by
reference until it diverges.

## Compatibility contract

- Triplet stays `x86_64-akadata-linux-musl`. No toolchain change.
- ABI stays musl-compatible (additive only, no symbol removal/rename).
- Loader stays `/lib/ld-musl-x86_64.so.1`; layout stays
  `--prefix=/usr --sysconfdir=/etc --syslibdir=/lib
  --localstatedir=/var`; CRT/TLS/pthread/static-PIE preserved.
- Payload paths intentionally collide with `musl`/`musl-dev`.
  Installing sinew beside musl is unsupported.

## Replacement model (investigation only, NOT activated)

APK supports `replaces=`/`provides=` for rename-in-place migration
(precedent: `gcc replaces="gcc-dev"`, `haproxy`/`haproxy-systemd`
mutual pair). A future production sinew would likely ship:

```
# provides="musl=1.2.6-r7 musl-dev=1.2.6-r7"
# replaces="musl musl-dev"
```

plus a safe migration path: same-loader swap (musl's linker is part
of the shared-libc implementation, reached via symlink — not an
independent loader to hot-swap), sysroot alignment (native headers,
crt, linker, cross-toolchain agreement; resolves the inherited 0003
split), and full dynamic/static/static-PIE + C/C++/pthreads/TLS +
existing Saphira suite validation. None of this is declared in
`recipe.sh` today. No publication, signing, installation, or upgrade
is authorised from this experimental recipe.

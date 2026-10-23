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

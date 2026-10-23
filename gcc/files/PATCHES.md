# gcc patches

Convention: `PATCHES.md` sits beside the patches it documents. Every
patch states why it exists and what breaks without it. See
`musl/files/PATCHES.md` for the full convention statement.

| File | Why | Upstreamable? |
|---|---|---|
| `0001-x86-increase-generic-tune-branch-misprediction-cost.patch` | Intentional Saphira compiler policy: AKADATA backport of upstream commit 52cd02606b906160bf47001a00b446c35d46f15f (`x86: Increase generic tune branch misprediction cost`, `COSTS_N_INSNS (2)` → `+ 3`). Inherited from the bootstrap; must be preserved across GCC upgrades, verified against new sources, never silently dropped. Removal is an explicit reviewed toolchain decision. | N/A (it IS upstream, backported). |
| `0002-m64-multilib-osdir-lib-not-lib64.patch` | Multilib osdir must be `/lib`, not `/lib64`: `/lib64` and `/usr/lib64` are forbidden in seeds and payloads (enforced by `makepkg`). Without it the toolchain resolves into forbidden directories. | No — Saphira layout. |

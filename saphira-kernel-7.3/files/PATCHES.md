# saphira-kernel-7.3 patches

Convention: `PATCHES.md` sits beside the patches it documents. Every
patch states why it exists and what breaks without it. See
`musl/files/PATCHES.md` for the full convention statement. All kernel
lines (7.1.5, 7.2.2, 7.2.3, 7.3-rc1, 7.3) carry the same pair.

| File | Why | Upstreamable? |
|---|---|---|
| `x86-64-v3.patch` | Saphira microarchitecture baseline: build the kernel at x86-64-v3 instead of baseline x86-64. Without it the kernel targets the lowest common denominator. | No — Saphira platform policy. |
| `cfg80211-regdb-freedom.patch` | Regulatory freedom: flips the two regdb-signature Kconfig gatekeepers y→n so an absent regulatory database can never resolve to enforced verification. A signed db may still ship; it must never be required. Proven by the `check-regdb-freedom.sh` build gate, which fails the build if enforcement recurs. | No — Saphira policy. |

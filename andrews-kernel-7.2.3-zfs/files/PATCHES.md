# andrews-kernel-7.2.3-zfs patches

Independence rule: this recipe owns its patch inputs as local copies
instead of referencing sibling recipe trees, so the build cannot drift
when those lines move. Every file below is byte-identical to its
source at vendoring time; if a source line updates its patch, copy the
new bytes here deliberately (never symlink, never auto-sync).

Kernel freedom patches (copies of `saphira-kernel-7.2.3/files/`).
Both copies carry the exact 7.2.3 upstream context and every
application site fails closed on fuzz or offset.

| File | Why | Upstreamable? |
|---|---|---|
| `x86-64-v3.patch` | Microarchitecture baseline: build at x86-64-v3 instead of baseline x86-64. Without it the kernel targets the lowest common denominator. | No — platform policy. |
| `cfg80211-regdb-freedom.patch` | Regulatory freedom: flips the two regdb-signature Kconfig gatekeepers y→n so an absent regulatory database can never resolve to enforced verification. Proven by the `check-regdb-freedom.sh` build gate. | No — policy. |

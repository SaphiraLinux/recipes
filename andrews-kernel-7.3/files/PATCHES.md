# andrews-kernel-7.3 patches

Independence rule: this recipe owns its patch inputs as local copies
instead of referencing sibling recipe trees, so the build cannot drift
when those lines move. Every file below is byte-identical to its
source at vendoring time; if a source line updates its patch, copy the
new bytes here deliberately (never symlink, never auto-sync) and note
it in the recipe header.

Kernel freedom patches (copies of `saphira-kernel-7.3/files/`, see
https://articles.akadata.co.uk/when-the-kernel-turns-against-you-linux-freedom-of-choice/):

| File | Why | Upstreamable? |
|---|---|---|
| `x86-64-v3.patch` | Microarchitecture baseline: build at x86-64-v3 instead of baseline x86-64. Without it the kernel targets the lowest common denominator. | No — platform policy. |
| `cfg80211-regdb-freedom.patch` | Regulatory freedom: flips the two regdb-signature Kconfig gatekeepers y→n so an absent regulatory database can never resolve to enforced verification. Proven by the `check-regdb-freedom.sh` build gate. | No — policy. |

OpenZFS 7.3 compat patches (copies of `saphira-zfs-7.3/files/`,
same set, order and exactness rules as that line's `000*` loop):

| File | Why |
|---|---|
| `0001-upstream-79fc679-bvec-bi-offset.patch` | Upstream OpenZFS `79fc679`: bvec `bi_bvec_done` renamed `bi_offset`. Without it the tree does not compile against 7.3 block layer headers. |
| `0002-saphira-7.3-kthread-fs.patch` | Run ZFS kthreads with init fs context. Without it I/O workers inherit the wrong filesystem context. |
| `0003-saphira-7.3-cpu-feature.patch` | `cpu_feature_enabled()` over `static_cpu_has()`. Without it capability detection miscompiles on 7.3. |
| `0005-saphira-7.3-inode-create.patch` | `iops->create()` without the removed flag argument. Without it the VFS glue does not match 7.3. |
| `0006-saphira-7.3-idmap-era.patch` | Treat 7.3 as mnt_idmap-era. Without it idmapped mounts mishandle ownership. |

The `zfs-2.4.4-linux-7.3-combined.patch` one-shot composite is
deliberately NOT vendored here (review artifact, never applied).

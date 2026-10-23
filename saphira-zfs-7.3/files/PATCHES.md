# saphira-zfs-7.3 patches

Convention: `PATCHES.md` sits beside the patches it documents. The
`000*` loop in `recipe.sh` applies the five numbered patches in order.
`zfs-2.4.4-linux-7.3-combined.patch` is the same five concatenated as a
one-shot alternative (see `README-7.3-compat.md`); it is intentionally
not applied by the loop. Full story (first ZFS on Linux 7.3, fio/scrub
evidence, Minimer proof) lives in that README, not here.

| File | Why | Upstreamable? |
|---|---|---|
| `0001-upstream-79fc679-bvec-bi-offset.patch` | Upstream OpenZFS `79fc679`: bvec `bi_bvec_done` renamed `bi_offset`, rebased to 2.4.4. Without it the tree does not compile against 7.3 block layer headers. | Yes — it IS upstream, backported. |
| `0002-saphira-7.3-kthread-fs.patch` | Saphira 7.3 port: run ZFS kthreads with init fs context (re-derived for 2.4.4). Without it I/O workers inherit the wrong filesystem context. Attribution: Muse Spark 1.3 Contributor for AKADATA LIMITED. | Possibly, if upstream takes a 7.3 port in this shape; not submitted. |
| `0003-saphira-7.3-cpu-feature.patch` | Saphira 7.3 port: `cpu_feature_enabled()` over `static_cpu_has()` (re-derived for 2.4.4). Without it capability detection miscompiles on 7.3. | Same as 0002. |
| `0005-saphira-7.3-inode-create.patch` | Saphira 7.3 port: `iops->create()` without the removed flag argument (re-derived for 2.4.4). Without it the VFS glue does not match 7.3. | Same as 0002. |
| `0006-saphira-7.3-idmap-era.patch` | Saphira 7.3 port: treat 7.3 as mnt_idmap-era (re-derived for 2.4.4). Without it idmapped mounts mishandle ownership. | Same as 0002. |
| `zfs-2.4.4-linux-7.3-combined.patch` | One-shot concatenation of the five above for reviewers applying by hand. Deliberately NOT applied by the recipe loop. | N/A (composite). |

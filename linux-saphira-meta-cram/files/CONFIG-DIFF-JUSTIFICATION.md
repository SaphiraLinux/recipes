# CONFIG-DIFF-JUSTIFICATION — 7.2.2 baseline vs 7.2.9-meta-cram (resolved)

Method: `config-7.2.2-akadata` + `cram-config.fragment`, resolved by
`make olddefconfig` against the patched 7.2.9 tree. The no-initramfs
builtin gate (`check-no-initramfs-builtins.sh 7.2.9`) passes on the
result. Families below cover every newly-enabled symbol and every
symbol flipped off.

## 1. Intentional: CRAM + test-backend closure (the fragment)

- `CRAM=y` — the goal. Deps already y (NUMA, MIGRATION, MEMORY_HOTPLUG,
  MEMORY_HOTREMOVE, COMPACTION, TRANSPARENT_HUGEPAGE for DEV_DAX).
- `DAX=m, DEV_DAX=m, DEV_DAX_PMEM=m, DEV_DAX_KMEM=m` — differentiated
  memory path: pmem device -> dax -> kmem onlining. KMEM's `private=1`
  is the documented CRAM instantiation path. All modules: nothing new
  built into vmlinuz, boot/root/network path untouched.
- `LIBNVDIMM=m, BLK_DEV_PMEM=m, ACPI_NFIT=m` (+ auto `NVDIMM_PFN=y,
  NVDIMM_DAX=y, MEMREGION=y, ND_CLAIM=y, ND_BTT=m, ND_PFN=m`) — NVDIMM
  bus + NFIT parsing so QEMU `-device nvdimm` presents test memory;
  `memmap=nn!ss` works through the same BLK_DEV_PMEM without hardware.
- `LOCALVERSION="-meta-cram"` — distinct modules dir + image name;
  the normal kernel stays the fallback.

Explicitly NOT enabled: CXL_BUS and everything under it, FS_DAX,
ZSWAP, DAMON, NUMA_EMU. No broad CXL, no module explosion.

## 2. 7.2.9-new Kconfig defaults (accepted, upstream-default)

Console/framebuffer (matches Saphira EFI-framebuffer policy):
`FB_CORE=y, FB_DEVICE=y, FB_CFB_*=y, FB_IOMEM_*=y, FB_NOTIFY=y,
FONT_8x8=y, VT_HW_CONSOLE_BINDING=y`. `FONT_AUTOSELECT` flips to n as
a direct consequence (`def_bool y depends on !FONT_8x8...`) — the
console keeps an explicit font, no loss.

Core/arch (no policy impact): `ARCH_MEMORY_ORDER_TSO=y,
FUTEX_ROBUST_UNLOCK=y (+HAVE), SCHED_CACHE=y, GENERIC_BITREVERSE=y,
INITRAMFS_PRESERVE_MTIME=y` (inert without initramfs),
`KMALLOC_PARTITION_{CACHES,RANDOM}=y` (rename successor of
RANDOM_KMALLOC_CACHES, which flips off correspondingly).

Decompressors `DECOMPRESS_{GZIP,BZIP2,LZMA,XZ,LZO,LZ4,ZSTD}=y` and
`RD_{BZIP2,LZ4,LZMA,LZO,XZ}=y`: new initramfs-format selectors,
default y. Tiny, required for robust boot-image parsing; kept as
defaulted (same as any 7.2.9 build would).

Mesh submenu `BATMAN_ADV_{BLA,DAT,MCAST}=y` under unchanged
`BATMAN_ADV=m`: bool children of a module parent, affect only module
contents, no vmlinuz impact. Module `NETFILTER_NETLINK_OSF=m` (new).

NFSv4 security `NFS_V4_SECURITY_LABEL=y` (+ `CRYPTO_KRB5=y,
CRYPTO_KRB5ENC=y, CRYPTO_CTS=y, CRYPTO_CAMELLIA=y, CRYPTO_SHA1=y,
NFS_V4_2_READ_PLUS=y, NFS_V4_2_SSC_HELPER=y`): `NFS_V4_SECURITY_LABEL`
is `default y if NFS_V4_2 && SECURITY` in 7.2.9; the crypto is its
selected dependency set. Harmless without an LSM policy labelling NFS;
kept as defaulted.

Misc: `NET_VENDOR_ALIBABA=y` (empty vendor menu), `PPPOX=y`
(selected by unchanged `PPPOE=y`), `RUSTC_HAS_APXF` /
`RUSTC_HAS_SUSPICIOUS_*` (toolchain disclosure lines only).

## 3. Upstream removals/renames (no action — nothing to preserve)

These symbols no longer exist in 7.2.9 Kconfig; any 7.2.9 build drops
them identically: `NFS_V4_1`, `NFSD_V3`, `NFSD_V4_2` (NFS version
splits reworked), `NF_TABLES_OSF` + `NETFILTER_NETLINK_ROUTE` (OSF
stack removal — also takes `IP_ROUTE_CLASSID` with it, now a bare
unsolicited bool nothing selects), `PCIE_BUS_DEFAULT` (+ siblings;
PCIe tuning choice removed, single behavior), `READ_ONLY_THP_FOR_FS`,
`GENERIC_TIME_VSYSCALL`, `PREFIX_SYMBOLS`,
`RANDOM_KMALLOC_CACHES` (renamed, see §2),
`ARCH_SUPPORTS_{AUTOFDO,PROPELLER}_CLANG` (toolchain feature probes).

## 4. Toolchain disclosure (build-env, not policy)

`CC_VERSION_TEXT`/`GCC_VERSION` (16.1.0 -> 16.2.0),
`RUSTC_VERSION` (1.97 -> 1.98): refreshed by olddefconfig from the
running toolchain; the builder re-resolves these at build time.

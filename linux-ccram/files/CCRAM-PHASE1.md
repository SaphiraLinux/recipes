# CCRAM-PHASE1 — what this kernel carries beyond linux-saphira-meta-cram

CCRAM — AKADATA LIMITED adaptation of Meta CRAM.  CCRAM is based on
Meta's CRAM work (Gregory Price; see CRAM.PROVENANCE in
linux-saphira-meta-cram) and extends/adapts it for Saphira Linux and
AKADATA LIMITED's tiered-memory experiments.  Meta's CRAM mechanism is
used as-is (no CRAM file is modified, no CRAM term renamed); the
`files/ccram/` patches below are Saphira-original integration code
(GPL-2.0-only).

Base: the complete meta-cram series (85 UPSTREAM + 19 FWD +
2 SKIP-UPSTREAM + 16 SKIP-FWD, byte-identical upstream files under
files/series/ and documented 7.2.9 adaptations under files/fwd/;
see CRAM.PROVENANCE and GATE-REPORT.md inherited from that recipe).

On top, four Saphira-original unit patches under files/ccram/:

- `ccram-01-sysram-params-pick.patch` — Kconfig option
  (`CONFIG_CCRAM_SYSRAM`), build glue, entry-point declarations,
  `ccram=` / `ccram.normal_min=` parsing, top-down reservation-aware
  range pick with the hard normal-RAM floor, fail-closed framework.
- `ccram-02-sysram-excise.patch` — early excision (`memblock_remove()`
  + e820 RAM→RESERVED retype) from a `setup_arch` hook before
  `init_mem_mapping()` (the window is never boot-mapped), plus the
  synthetic-nid helper.
- `ccram-03-sysram-topology.patch` — post-`initmem_init()` validation
  (re-check vs late reservations, fail closed), synthetic nid
  reservation, commit with unambiguous `[start-end]` diagnostics.
- `ccram-04-sysram-register.patch` — late `cram_register()` at 1:1
  (honest uncompressed value), `N_MEMORY_PRIVATE` via CRAM, read-only
  debugfs accounting plus write-only pass-throughs to CRAM's own
  controls.
- New files: `mm/ccram_sysram.c` (~440 lines, grown across 01–04),
  `include/linux/ccram_sysram.h`. Touched: `mm/Kconfig`, `mm/Makefile`,
  `arch/x86/kernel/setup.c` (two hook sites + include).

Behavior contract (functional backend ONLY — not compressed RAM):

- `ccram=<size|percent%>` + `ccram.normal_min=` (default 4G). Absent
  parameter: kernel behaves exactly like meta-cram (info line at boot).
- Two-phase carve (r5+; earlier revs carved post-map and tripped a
  phys_pud split WARN on every boot — fixed at the root, no generic
  code touched, no diagnostic weakened):
  - Phase A, pre-`init_mem_mapping()`: parse, top-down pick vs
    currently-reserved, `memblock_remove()`, e820 RAM→RESERVED retype
    (full-window or refuse). The window is therefore never boot-mapped
    (the boot map is built from memblock), so the later hot-add maps
    virgin slots. Same excision primitive `mem=` uses, scoped.
  - Phase B, post-`initmem_init()`: re-validate vs memblock.reserved
    (NODE_DATA, crashkernel, initrd, CMA all placed by now) — overlap
    fails closed with the window left excised (healthy boot, less RAM,
    loud error); then reserve the synthetic nid (SRAT known) and commit.
- Carve: highest 128M-aligned range fitting the request, reserved
  overlap fails closed, normal_min floor enforced (refuse, never
  starve DRAM).
- Diagnostics print unambiguous [start-end] (inclusive); the r1-r4
  lines printed [start-size] and read backwards.
- nid: first non-possible id (never collides with firmware nodes);
  possible-map + offline node data allocated in setup_arch, because
  node_private_register() dereferences NODE_DATA before the hotplug
  path runs (verified constraint, see CCRAM-GATE1-OWNERSHIP.md).
- Late: `cram_register(nid, ranges, 1, 1000 /*1:1 honest*/, {NULL},
  NULL)` — CRAM owns np registration (caps RECLAIM|HOTUNPLUG|
  WRITE_FENCE), hotplug as N_MEMORY_PRIVATE, movable online, kswapd.
  WRITE_FENCE ON and NUMA_BALANCING OFF per the approved decisions.
- Observability: /sys/kernel/debug/ccram/{start,size,nid,
  compression_ratio,allow_allocation} + the standard CRAM counters.
  Synthetic pressure reuses cram_set_compression_ratio /
  cram_allow_allocation; no private pressure wheel.

Phase 2 (mm/ccram.c, LZ4 tier) is a separate milestone with its own
series; nothing here preempts its file or symbol names (ccram_*).

# CCRAM Gate 1 — carve-out ownership path (must hold before Phase 1 code)

Claim under test: ordinary DRAM can be removed from the normal allocator
at boot and re-registered later as an N_MEMORY_PRIVATE node with no
resource collision and no silent reuse.

## Proven by code reading (7.2.9 tree as forward-ported)

1. **Removal hides memory from the buddy.** `memblock_remove(base, size)`
   (`mm/memblock.c:888`) deletes the range from `memblock.memory`
   entirely (not merely reserved). `free_area_init_nodes()` /
   `memblock_free_all()` only ever hand `.memory` ranges to the buddy,
   so a removed range can never back slab, page tables, DMA, or
   userspace. (`memblock_reserve()` would be wrong here — reserved
   ranges stay in `.memory`.)
2. **No "System RAM" iomem resource is created for it.**
   `request_standard_resources()` builds "System RAM" entries by walking
   `memblock.memory`. A removed range gets no entry.
3. **Late registration cannot collide.** `add_private_memory_driver_managed()`
   → `__add_memory_driver_managed()` → `register_memory_resource()` →
   `__request_region(&iomem_resource, ..., "System RAM (ccram)",
   SYSTEM_RAM|BUSY|SYSRAM_DRIVER_MANAGED)`, which fails closed with
   `-EEXIST` on a BUSY conflict (`mm/memory_hotplug.c:276-308`). Absent
   prior resource ⇒ clean creation. The name format is enforced
   (`-EINVAL` otherwise). The DRIVER_MANAGED flag additionally keeps
   kexec images off the range — free bonus, same rationale as the
   upstream docblock.
4. **Private state follows registration.** `online_pages()` sets
   `N_MEMORY_PRIVATE` iff `pgdat_is_private(NODE_DATA(nid))`, i.e. iff
   our `node_private` was registered (`mm/memory_hotplug.c:1206-1211`).
   `node_private_register()` refuses `-EBUSY` when the node is already
   N_MEMORY — so a range that leaked into normal use fails loudly at
   registration, exactly the "bear-proof" property we want. DEMOTION
   without RECLAIM is refused (`-EINVAL`); CCRAM sets both.
5. **New-node pgdat exists.** `__add_memory_resource()` →
   `__try_online_node()` → `hotadd_init_pgdat()` allocates/initialises
   the pgdat and rebuilds zonelists for new nodes
   (`mm/memory_hotplug.c:1300-1320,1264-1287`).

## Open items (resolve while writing Phase 1, before enabling by default)

a. **Possible-map membership.** `__add_memory_resource()` WARNs +
   `-EINVAL` on `!node_possible(nid)`. A firmware-unknown nid is not in
   x86's map (built from SRAT in `arch/x86/mm/numa.c`). CCRAM must add
   it (direct `node_set()` on the possible map) — verify against
   `node_possible_map` handling for memoryless nodes.
b. **NODE_DATA ordering.** `node_private_register()` dereferences
   `NODE_DATA(nid)` but runs *before* `__try_online_node()`. x86
   `alloc_node_data()` (`arch/x86/mm/numa.c:145`) only covers
   firmware-described nodes with ranges. Confirm what `NODE_DATA(nid)`
   contains for a fresh nid (free_area_init "preallocation" per the
   `hotadd_init_pgdat` comment) and, if NULL, initialise it explicitly
   on the CCRAM path before registering. This is the single riskiest
   line of Phase 1; get it wrong and registration oopses.
c. **Carve-time validation.** Before `memblock_remove()`: range must be
   section/subsection-aligned and a multiple of
   `memory_block_size_bytes()` (enforced later by
   `check_hotplug_memory_range()` — fail early instead); must not
   overlap any `.reserved` entry (`memblock_overlaps_region()`);
   prefer the highest suitable range; enforce `ccram.normal_min`
   (default several GiB) as a hard floor, refusing the carve-out
   otherwise. 16G first; 25%/50%/80%+ only after 16G passes.
d. **Hook point.** `ccram=` is an `early_param` (stashes request);
   the `memblock_remove()` itself runs immediately after
   `e820__memblock_setup()` in `setup_arch()` — i.e. next to `memmap=`
   handling (`arch/x86/kernel/e820.c:1012`), NOT near TME init (see
   TME verdict in planning notes: TME reserves nothing and marks no
   pages; the only real interaction is computing against the effective
   physical mask on TME-MK systems).

## Empirical proof procedure (QEMU, after base green)

1. Boot test kernel with `ccram=16G` (large-memory QEMU guest).
   Expect: dmesg shows the memblock removal; `/proc/iomem` shows NO
   "System RAM" over the range pre-registration and
   `System RAM (ccram)` post-registration.
2. `/sys/devices/system/node/` gains the node; `has_private_memory`
   set; node absent from default zonelists (`/proc/zoneinfo`,
   `numactl --hardware` residency).
3. `malloc()` storm cannot land there (numa_maps residency stays zero
   without explicit placement); `mbind()`/`move_pages()` with
   CAP_USER_NUMA can; reclaim demotion arrives under pressure.
4. Write to a demoted page promotes back to DRAM (fault counters +
   residency move); `cram/control block/unblock` + ratio changes move
   demotion behavior observably.
5. Exhaustion test: force the node full, confirm demotions stop,
   system survives, no corruption, dmesg pressure events.
6. Boot with `ccram=` absent: byte-identical behavior to base kernel
   (static-key-gated CRAM paths are NOPs; node absent).

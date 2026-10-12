# CCRAM Gate 2 — software-compressed page representation (design freeze
# before Phase 2 code; anon 4K only)

Invariant (non-negotiable): software-compressed bytes are NOT directly
CPU-addressable. A CCRAM object must never sit behind a present,
readable/writable PTE. Every CPU access faults, decompresses into an
ordinary DRAM folio, and restores the mapping. Phase 2 starts with
anonymous order-0 pages only; THP/shmem/page-cache are explicitly
excluded with clear rejection paths (file promotion already has its
own WRITE_FENCE machinery — do not entangle it).

## Representation decision: migration-style special entry, NOT a swap slot

Options considered:

- **A. New swap type** (consume one of the 32 `MAX_SWAPFILES` slots,
  `include/linux/swap.h:47-116`): rejected. It drags in swap
  accounting (`swap_info_struct`, clusters, discard paths, hibernation
  pinning), burns a scarce global type ID for a node-local concern,
  and invites exactly the "accidental zram" confusion this gate
  exists to prevent.
- **B. Special (non-swap) PTE marker in the migration-entry family:
  CHOSEN.** Precedent: migration entries (`softleaf_is_migration_*`),
  device-private entries, hwpoison — all non-present PTEs carrying an
  index in the offset field with custom fault dispatch, none of them
  consuming swap types or swap accounting. CCRAM defines
  `make_ccram_entry(obj_id)` / `is_ccram_entry()` / `ccram_entry_to_obj()`
  mirroring `make_migration_entry()`, with `obj_id` scoped to the
  CCRAM object store (per-node), NOT a global swap offset.

Architectural difference from zram, stated explicitly: zram is a
block-device swap consumer — allocation goes through swap slots and
the bio path, reclaimable only via the swap subsystem, invisible to
NUMA tiering. CCRAM objects live in a private-node tier, are placed by
reclaim demotion (`cram_migrate_to`), promoted by faults, accounted per
node, and governed by CRAM backpressure. Same compressor library,
different universe: tier vs swap device.

## Demotion path (anon 4K)

`shrink_folio_list()` → existing `cram_migrate_to()` hook diverts an
eligible anon folio → CCRAM: compress (LZ4) → allocate object in the
chunk store → `make_ccram_entry(obj_id)` installed via the
migration-entry install path (folio locked, rmap-checked, refcount
managed exactly like a migration entry) → source folio freed to the
DRAM buddy. Eligibility gate: `folio_test_anon && !folio_test_large &&
!folio_test_shmem && !folio_test_dirty` (dirty anon must write back
first — no silent data loss); everything else falls through to normal
reclaim.

## Fault path (read and write converge initially)

`handle_pte_fault()` non-present + `is_ccram_entry()` → CCRAM handler
(beside `do_swap_page`, not inside it): allocate ordinary DRAM folio
(`GFP_HIGHUSER_MOVABLE`, never from the CCRAM node) → decompress +
verify checksum → install present PTE (writable iff fault was a write
and VMA allows; read faults may install read-only to keep the object
alive for re-reads ONLY if the object is retained — initial policy:
always consume the object on fault, i.e. every fault is a promotion;
measure before adding residency) → free the object → update CCRAM
accounting. OOM during fault allocation fails the fault (SIGBUS path),
never dips into the CCRAM store for the destination.

## Object store sketch (bounded, DRAM-resident metadata)

- Chunk allocator: ordinary-order pages (start order-0/1) suballocated
  into variable-length objects; per-object record: compressed length,
  algorithm id, checksum, state (valid/in-flight/invalid), owning
  folio identity (for debugging/teardown only — lookup is
  entry→obj_id, never reverse-scanned).
- Metadata lives in normal DRAM, slab-accounted, with a hard cap
  (function of backing size); metadata exhaustion stops demotions
  before it can strand objects.
- Free path: `cram_ops.trim`-analogue (CCRAM-internal; the upstream
  `trim` callback stays NULL so CRAM zeroes — no, for CCRAM the
  backing IS DRAM: freed folios release their objects explicitly;
  nothing to scrub on device).

## Backpressure honesty

- No fixed ratio promised. Logical capacity == physical backing at
  registration; the *measured* ratio (real occupancy vs backing) is
  reported through the existing `cram_set_compression_ratio()` channel,
  making Phase 1's synthetic reports truthful in Phase 2.
- High watermark (~85% backing occupancy, tunable): stop new demotions
  (`cram_allow_allocation(false)` semantics), prefer dropping clean
  file pages where valid, promote under pressure; incompressible
  data (random/encrypted test corpuses mandatory) must degrade to
  "store uncompressed or refuse demotion", never corrupt.
- `normal_min` floor from Phase 1 now also covers decompression
  destinations: a fault that cannot allocate DRAM fails safely.

## Instrumentation required before any ratio/throughput claim

Per-object stats + node counters (demotions, promotions by
read/write, faults, decompress CPU ns, object-size histogram,
metadata bytes, watermark events, incompressible refusals) via the
`ccram/` debugfs tree from Phase 1. Benchmarks vs plain RAM / zram /
zswap under identical constraints come after, using the metric list in
the project brief (capacity, ratio, (de)compression CPU, fault
latencies, reclaim latency, throughput, tail latency, page-cache
behaviour, copies, metadata, incompressible behaviour, scarce-DRAM
behaviour).

# CCRAM-PHASE2B-DESIGN — residency wiring for anonymous 4K (implemented)

Status: implemented as `ccram-07` (encoding + fault-in + lifecycle)
and `ccram-08` (demote-store path); see implementation notes at the
end for deliberate deviations from this design.

CCRAM — AKADATA LIMITED adaptation of Meta CRAM (Saphira-original
integration; Meta's CRAM mechanism used as-is except for the defined
hook points listed below. GPL-2.0-only.)

Scope for the first usable version: **anonymous order-0 pages only**.
No ZFS/ARC, slab, file cache, huge pages, KSM, mlocked, or shared
beyond fork-COW semantics. File folios keep today's migrate-placement;
THP/KSM fall back to placement. ZFS/ARC stays outside CCRAM.

## Lifecycle (the required shape)

```
normal anonymous page
        │  reclaim / CCRAM eviction (shrink path, cram_folios list)
        ▼
compress page (per-CPU scratch, NORETRY fail-fast)
        ├── LZ4 if it saves ≥512B
        └── raw 8-unit object if incompressible
        ▼
store object in CCRAM node-1 pool (units on node-1 buddy pages, off-LRU)
        ▼
rmap-walk all mappings: replace present PTEs with CCRAM marker PTEs
(mmu_notifier invalidate + TLB flush — KVM EPT coherence depends on it)
        ▼
free original normal-RAM page (demote counts as reclaim)
```

Fault-in (read or write):
```
CPU fault on CCRAM marker
      ▼  handle_pte_marker branch (additive, before unknown-SIGBUS)
lookup object by id (refcounted borrow)
      ▼
allocate ordinary RAM page (fault context: may sleep, GFP_HIGHUSER_MOVABLE)
      ▼
fetch + LZ4_decompress_safe into it; xxh64 must match or fail closed
      ▼
install present anon PTE (writable iff VMA_WRITE and fault-write,
else read-only for later normal COW), rmap, LRU, memcg charge,
update_mmu_cache
      ▼
drop marker ref; object freed at zero. npromote++.
```

No swap, no swapfile, no zswap involvement at any point: the design
works swapless because the store itself is the backing.

## Non-present encoding (stop-condition: PASSED, no theft)

- `PTE_MARKER_CCRAM = BIT(3)`: next free marker bit alongside
  UFFD_WP/POISONED/GUARD (`PTE_MARKER_MASK` widens by OR — additive).
  Marker value = `CCRAM_BIT | (u32 obj_id << 3)` in the swap offset
  field; x86-64 carries 58 offset bits, we need 32. Id 0 stays invalid
  (store allocates from 1).
- Fault dispatch: one additive branch in `handle_pte_marker()`
  (`mm/memory.c`), before the unknown-marker SIGBUS fallthrough.
- Fork: `copy_one_pte()`'s marker branch + `copy_pte_marker()` must
  preserve our bit AND bump the object ref (else the child reads zeros
  after the parent frees). Two defined call sites
  (`mm/memory.c`, `mm/hugetlb.c` — latter documents small-page-only
  scope initially).
- munmap/exit: single hook in the `zap_pte_range()` marker path —
  drop the marker's ref (both munmap and exit teardown flow through
  unmap_page_range). No separate exit hook.
- mremap: moves PTEs verbatim, same mm — no hook, refcount unchanged.
- mprotect: markers preserved as-is (verify at implementation; no
  write-fence interaction since markers are non-present).
- Node offline/drain: refused while objects exist (fail closed);
  promote-all drain is future work. CCRAM never offlines nodes today.
- THP: order>0 never enters the swcompress path (placement fallback).

## Demote branch (exact hook point)

`mm/vmscan.c`: after the `cram_folios` list is built
(`shrink_folio_list`, ~L1597 `if (!list_empty(&cram_folios))`), before
`cram_migrate_to()`: split off swcompress candidates — anon,
order-0, mapped, not KSM, compress mode on with live store. For each:
folio_lock → store (NORETRY fail-fast; failure leaves it on the list
for today's migrate-placement) → rmap-walk replace-present-with-marker
(mmu_notifier + TLB flush, KVM-safe) → install all markers (one ref
each) → drop original ref (frees to node-0 buddy) → ndemote++.
Remainder flows into `cram_migrate_to()` unchanged.

Why rmap-walk instead of try_to_unmap: the folio has no swap entry
(and must never get one — that would be the swap subsystem by the back
door). The walk mirrors the migration-entry installer, but installs
our marker. Page lock held throughout; store-then-unmap ordering means
a concurrent fault either sees the old present page or the new marker,
never nothing.

## Fault handler (exact hook point)

New `ccram_marker_fault(vmf)` called from `handle_pte_marker()`.
Mirrors `do_anonymous_page`/`do_swap_page` discipline at reduced scope
(anon-only): memcg charge, fresh page, load+verify (fail → SIGBUS,
never a bad page), `page_add_new_anon_rmap`, LRU add (so it can be
re-demoted later — no cycle: each demote makes progress or falls
back), `update_mmu_cache`, drop marker ref, npromote++. Shared
fork markers each materialize a PRIVATE copy (no shared-object rmap —
correct COW semantics for free).

## GUP / KVM compatibility

- KVM EPT mirrors via mmu_notifier: our unmap invalidates (guest
  drops the mapping), next guest touch faults host-side and
  materializes. No special casing.
- GUP-fast on a marker fails → falls into fault → materializes, then
  pins the fresh normal page. `FOLL_LONGTERM` never touches the tier
  (fresh pages are node-0). No `CAP_LTPIN` interaction.

## move_pages / migrate_pages syscalls on markers

Out of scope initially: unrecognized-marker pages report per-page
failure (no crash, no corruption). QEMU guest RAM does not use these
paths. Documented limitation, not silent.

## Params, accounting, acceptance mapping

- Single switch stays `ccram.compress=off|lz4` (default off): off =
  today's placement bit-for-bit; lz4 = store + residency wiring.
- Store counters exist (physical/logical/stored/waste/ops/fails);
  wiring adds ndemote/npromote to the same debugfs table.
- Acceptance maps 1:1: anon-only workload (QEMU RAM) → objects rise
  under pressure → normal free recovers → cold touch faults exact
  bytes back (hash-verified) → shutdown (munmap/exit zap hooks) drains
  to zero → no BUG/WARNING/Oops.

## Explicitly deferred

ZFS/ARC/slab/file residency, THP, KSM, proactive (hot-page)
promotion, node-offline drain, quanta other than 512, USER_NUMA
placement (separate feature), move_pages support.

## Implementation notes (deliberate deviations from the above)

- Rollback restores minimal-safe protection (read-only clean young)
  via a second rmap walk instead of per-mapping saved PTEs: no
  bounded array, no overflow concept, same safety (a later write takes
  the normal COW fault). Simpler and strictly more robust.
- mprotect needs no change: verified the marker branch preserves
  non-poison/guard markers untouched.
- Demote re-checks eligibility under the folio lock (closes KSM/unmap/
  mode-change races to a negligible window; rmap walk remains
  authoritative).
- Source PTEs with uffd-wp armed abort to placement (tracking
  preserved by the path that understands it).
- Locking constitution holds as specified: store lock is a leaf under
  PTL everywhere (demote phases never nest them; fault splits lookup
  from install; fork/zap nest PTL→store only).

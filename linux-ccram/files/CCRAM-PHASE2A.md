# CCRAM-PHASE2A — software-compressed object store (unwired)

CCRAM — AKADATA LIMITED adaptation of Meta CRAM (Saphira-original
code, GPL-2.0-only; Meta's CRAM mechanism used as-is).

## Architectural position

Meta's CRAM assumes hardware compression: the driver contract is
`{trim}` plus a claimed ratio, and the core migrates whole folios onto
node pfns with present read-only residency.  A DRAM backend cannot gain
real capacity inside that model — present PTEs map whole frames, and
overcommit needs non-present encodings plus a fault path.  Phase 2A
therefore builds, in this order:

1. **Object store** (this patch): 4096-byte page → LZ4 → variable-sized
   object packed into 512-byte backing units; incompressible pages
   stored raw as 8 units.  Proven standalone by a deterministic
   self-test before any residency wiring.
2. **Residency wiring** (later patch): non-present PTE-marker encoding
   (`PTE_MARKER` has a free `BIT(3)` plus upper offset bits — a
   purpose-built extension point, not a theft), fault discharging
   (decompress to a fresh private page), demote-store/promote/fault
   paths, fork/exit/munmap lifecycle hooks, `ccram.compress` enforcement.

The proven Phase 1 path (carve/topology/registration, 1:1 placement)
is untouched; `ccram.compress=off` (default) preserves r6 behaviour
bit-for-bit.

## Reuse audit (summary; full rationale in mm/ccram_store.c header)

- REUSED: lib/lz4 (`LZ4_compress_default`, `LZ4_decompress_safe`,
  caller-provided work area fits per-CPU scratch), xxhash64
  (post-decompression verification; LZ4 carries no checksum).
- NOT reused: zsmalloc (node affinity exists, but the quantum
  experiment needs an exact 512-byte packer with exact waste
  accounting, free of shrinker/compaction entanglement — recorded as
  the evaluated upgrade path), zswap/zpool (frontswap-tied / absent),
  async crypto (sleeping, unsuitable for reclaim context).

## Representation

- Logical identity: one 4K page. Object meta (xarray id→struct):
  original length (4096), stored length, algo/flags
  (`CCRAM_OBJ_RAW`, `CCRAM_OBJ_ALGO_LZ4`), xxh64 of original, backing
  unit list, refcount. Handle: u32 id (ids from 1; 0 invalid).
- Backing: chunk pages on the store's node (movable, held off-LRU so
  reclaim cannot see them), 8×512B units each, bitmap tracked, empty
  chunks returned to the buddy. Unit numbers monotonic, never reused.
- Tail padding zeroed (no stale bytes in waste). Raw fallback = 8
  units, uniform free path. Exact-once release: erase-then-release
  refcounting; double free is silent -ENOENT; destroy refuses live
  objects; leak balance proven by self-test.

## Recursion/locking

Per-CPU scratch only for transforms; every store allocation is
`NORETRY|NOWARN` fail-fast with caller fallback (pool growth happens
outside the single store spinlock in bounded rounds); xarray ops under
the lock use NOWAIT-inherited GFP. Fault/load holds refs across the
lock-free decompress+verify window.

## Params, accounting, observability

- `ccram.compress=off|lz4`, default off. With `lz4`: a live store is
  created on the first CRAM node and the self-test runs once on a
  throwaway store; self-test failure disables compression (tier keeps
  serving 1:1, fail closed).
- Counters: physical backing bytes, logical bytes, stored bytes,
  packing waste, compressed/raw pages, compress/decompress ops,
  failures (demotion/promotion counts arrive with residency wiring).
- Reported ratios: logical/stored (true compression) and
  logical/physical (with waste) — padding can never fake the first.
- debugfs (under `ccram/`): `store_stats` (0444), `selftest` (0200,
  reruns the proof on a throwaway store).

## Self-test cases (deterministic)

zeros, ones, 8-byte repeat, counter, alternating bits, text-like,
random (expects raw fallback), half-zero/half-random. Each: store →
class check → load → memcmp + independent hash compare → free →
silent double-free refusal. Ends with leak balance (objs/phys/logical
all zero) and store destroy. PASS/FAIL in dmesg.

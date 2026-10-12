# GATE-REPORT — per-patch disposition (all 103 upstream commits accounted)

Gate: sequential `git apply --check` against pristine linux-7.2.9, in
chronological order. Statuses: APPLIED = byte-identical upstream applied;
SKIP-UPSTREAM = already in 7.2.9 (forward fails, reverse-check clean);
SKIP-FWD = upstream does not apply; adapted equivalent in files/fwd/.

- 001 mm vmstat  fold stranded per-cpu node stats when a node come
  SKIP-UPSTREAM: already merged upstream (in 7.2.9 tree; reverse-check clean)
- 002 mm  constify oom control  scan control  and alloc context no
  APPLIED byte-identical.
- 003 mm mm init  handle alloc percpu failure in free area init co
  SKIP-UPSTREAM: already merged upstream (in 7.2.9 tree; reverse-check clean)
- 004 mm memory  add memory block aligned range   helper 
  APPLIED byte-identical.
- 005 mm memory hotplug  add mhp online type to str   and export s
  APPLIED byte-identical.
- 006 mm memory hotplug  pass online type to online memory block  
  APPLIED byte-identical.
- 007 mm memory hotplug  export mhp get default online type 
  APPLIED byte-identical.
- 008 mm memory hotplug  add   add memory driver managed   with on
  APPLIED byte-identical.
- 009 mm memory hotplug  add offline and remove memory ranges   
  APPLIED byte-identical.
- 010 dax kmem  resolve default online type at probe time 
  APPLIED byte-identical.
- 011 dax kmem  extract hotplug hotremove helper functions 
  APPLIED byte-identical.
- 012 dax kmem  add sysfs interface for atomic whole-device hotplu
  APPLIED byte-identical.
- 013 selftests dax  add dax kmem hotplug sysfs regression test 
  APPLIED byte-identical.
- 014 mm  refactor find next best node to find next best node in 
  SKIP-FWD -> fwd/014-fwd-7.2.9-find_next_best_node_in.patch
  why: branch carries akpm-7.3 node_reclaim() signature (int, anonymous params, NOSCAN stub); 7.2.9 differs. Only the two internal.h hunks refreshed.
- 015 mm page alloc  refactor build node zonelist   out of build z
  APPLIED byte-identical.
- 016 mm page alloc  let the bulk and folio allocators carry alloc
  SKIP-FWD -> fwd/016-fwd-7.2.9-carry-alloc-flags.patch
  why: branch base carries akpm-7.3 alloc-flags plumbing (mm/page_alloc.h, ac.alloc_flags); 7.2.9 predates it. Same capability rebuilt in 7.2.9 shape (gfp.h/internal.h); all callers pass ALLOC_DEFAULT/0 (behavior-preserving).
- 017 numa  introduce N MEMORY PRIVATE 
  SKIP-FWD -> fwd/017-fwd-7.2.9-n-memory-private.patch
  why: 7.2.9 moved the sysctl-decl anchors and reordered comments; helpers re-anchored at folio_batch + page-table-move comment. Rest verbatim.
- 018 mm  add ZONELIST PRIVATE  NOFALLBACK  for N MEMORY PRIVATE n
  SKIP-FWD -> fwd/018-fwd-7.2.9-zonelist-private.patch
  why: no mm/page_alloc.h in 7.2.9 (decls in gfp.h/internal.h); no NOLOCK WARN_ON site (7.3 material absent). ALLOC_ZONELIST_PRIVATE (0x2000) + select_zonelist() live in internal.h. Rest verbatim; diffstat identical (109+/5-).
- 019 cpuset  exclude private nodes from cpuset.mems  default-open
  APPLIED byte-identical.
- 020 mm memory hotplug  disallow migration-driven private node ho
  APPLIED byte-identical.
- 021 mm mempolicy  skip private node folios when queueing for mig
  APPLIED byte-identical.
- 022 mm migrate  disallow userland driven migration for private n
  APPLIED byte-identical.
- 023 mm madvise  disallow madvise operations on private node foli
  APPLIED byte-identical.
- 024 mm compaction  disallow compaction on private nodes 
  APPLIED byte-identical.
- 025 mm page alloc  clear private node watermarks and system rese
  APPLIED byte-identical.
- 026 mm mempolicy  disallow NUMA Balancing prot none on private n
  APPLIED byte-identical.
- 027 mm damon  skip private node memory in DAMON migration and pa
  SKIP-FWD -> fwd/027-fwd-7.2.9-damon-skip.patch
  why: 7.2.9 DAMON migrate path has extra node_stat_add_folio accounting; guard placement kept, context refreshed.
- 028 mm ksm  skip KSM for managed-memory folios 
  APPLIED byte-identical.
- 029 mm khugepaged  skip private node folios when trying to colla
  APPLIED byte-identical.
- 030 mm vmscan  disallow reclaim of private node memory 
  APPLIED byte-identical.
- 031 mm gup  disallow longterm pin of private node folios 
  APPLIED byte-identical.
- 032 proc  include N MEMORY PRIVATE nodes in numa maps output 
  SKIP-FWD -> fwd/032a + fwd/032b (split pair, order matters)
  why: content verbatim upstream, but the pmd/pte twin hunks share
  near-identical context, which patch(1) refuses as ambiguous (it will
  not pick between two perfect matches). Split into an ordered pair:
  032a carries the pmd hunk with trailing context to the pmd-only
  #endif (unique); 032b carries the pte + display hunks (unambiguous
  once the twin is converted). No logic change.
- 033 mm memcontrol  account private-node memory in per-node stats
  SKIP-FWD -> fwd/033-fwd-7.2.9-memcontrol-reportable.patch
  why: 7.2.9 rstat_flush() has a second (events) aggregate pass; decl + loop hunks refreshed to that shape.
- 034 proc kcore  include private-node RAM in the kcore RAM map 
  APPLIED byte-identical.
- 035 mm mempolicy  add MPOL F PRIVATE and zonelist selection 
  APPLIED byte-identical.
- 036 mm mempolicy  apply policy at the kernel zone for private-no
  APPLIED byte-identical.
- 037 mm mempolicy  add in-kernel MPOL BIND interfaces for drivers
  APPLIED byte-identical.
- 038 mm memory hotplug  support N MEMORY PRIVATE node hotplug 
  APPLIED byte-identical.
- 039 mm  add NODE PRIVATE CAP RECLAIM for opted-in private node r
  SKIP-FWD -> fwd/039-fwd-7.2.9-cap-reclaim.patch
  why: no mm/page_alloc.h in 7.2.9; node_private.h include slots into compaction.c directly. Logic verbatim.
- 040 mm  add NODE PRIVATE CAP USER NUMA for userland numa control
  APPLIED byte-identical.
- 041 mm  add NODE PRIVATE CAP HOTUNPLUG for opted-in private node
  APPLIED byte-identical.
- 042 mm  add NODE PRIVATE CAP DEMOTION for private-node tiering d
  APPLIED byte-identical.
- 043 mm  add NODE PRIVATE CAP NUMA BALANCING for private-node NUM
  APPLIED byte-identical.
- 044 mm  add NODE PRIVATE CAP LTPIN for private node folio pinnin
  APPLIED byte-identical.
- 045 mm khugepaged  base private node collapse eligiblity on acto
  APPLIED byte-identical.
- 046 Documentation mm  describe private  N MEMORY PRIVATE  memory
  APPLIED byte-identical.
- 047 mm mempolicy  add mpol set shared policy range   
  SKIP-FWD -> fwd/047-fwd-7.2.9-shared-policy-range.patch
  why: branch base has 7.3-bound vma_start/end_pgoff() helpers; 7.2.9 open-codes vma->vm_pgoff + vma_pages() (identical arithmetic).
- 048 KVM  guest memfd  bind backing memory to a NUMA node at crea
  APPLIED byte-identical.
- 049 KVM  selftests  add a guest memfd FLAG BIND NODE test 
  APPLIED byte-identical.
- 050 dax kmem  add dax file  to expose an anonymous-fault char de
  APPLIED byte-identical.
- 051 dax kmem  add private  to online memory as an N MEMORY PRIVA
  APPLIED byte-identical.
- 052 dax kmem  add the reclaim opt-in  CAP RECLAIM  for private n
  APPLIED byte-identical.
- 053 dax kmem  add the user numa opt-in  CAP USER NUMA  for priva
  APPLIED byte-identical.
- 054 dax kmem  add the hotunplug opt-in  CAP HOTUNPLUG  for priva
  APPLIED byte-identical.
- 055 dax kmem  add the demotion and numa balancing opt-ins for pr
  APPLIED byte-identical.
- 056 dax kmem  add the ltpin opt-in  CAP LTPIN  for private nodes
  APPLIED byte-identical.
- 057 dax kmem  add dax adistance to make private node adistance c
  APPLIED byte-identical.
- 058 selftests dax  add the private-node test harness 
  APPLIED byte-identical.
- 059 selftests dax  add private-node capability hotplug ABI test 
  APPLIED byte-identical.
- 060 selftests dax  add dax dax file test on a public kmem node 
  APPLIED byte-identical.
- 061 selftests dax  add private-node placement isolation test 
  APPLIED byte-identical.
- 062 selftests dax  add private-node longterm-pin  CAP LTPIN  tes
  APPLIED byte-identical.
- 063 selftests dax  add private-node pressure isolation test 
  APPLIED byte-identical.
- 064 selftests dax  add private-node reclaim test 
  APPLIED byte-identical.
- 065 selftests dax  add private-node compaction tests 
  APPLIED byte-identical.
- 066 selftests dax  add private-node cpuset default-open test 
  APPLIED byte-identical.
- 067 selftests dax  add private-node mbind   test 
  APPLIED byte-identical.
- 068 selftests dax  add private-node set mempolicy   test 
  APPLIED byte-identical.
- 069 selftests dax  add private-node mempolicy rebind test 
  APPLIED byte-identical.
- 070 selftests dax  add private-node move pages   test 
  APPLIED byte-identical.
- 071 selftests dax  add private-node migrate pages   test 
  APPLIED byte-identical.
- 072 selftests dax  add private-node demotion  CAP DEMOTION  test
  APPLIED byte-identical.
- 073 selftests dax  add private-node hotplug transition test 
  APPLIED byte-identical.
- 074 selftests dax  add private-node observability test 
  APPLIED byte-identical.
- 075 selftests dax  add private-node THP collapse test 
  APPLIED byte-identical.
- 076 selftests dax  add private-node page-table placement test 
  APPLIED byte-identical.
- 077 selftests dax  add dax adistance tests 
  APPLIED byte-identical.
- 078 Documentation dax  dax kmem private-node ABIs 
  APPLIED byte-identical.
- 079 Documentation dax  document adistance attribute 
  APPLIED byte-identical.
- 080 Documentation mm  add testing section for N MEMORY PRIVATE n
  APPLIED byte-identical.
- 081 sched numa  export a promotion rate-limit check for device-d
  APPLIED byte-identical.
- 082 mm  add NODE PRIVATE POLICY WRITE FENCE for read-only privat
  SKIP-FWD -> fwd/082-fwd-7.2.9-write-fence-policy.patch
  why: 7.2.9 internal.h ends differently (may_expand_vm, no can_spin_trylock tail); node_placement_check() anchored at file-end guard. Body verbatim.
- 083 mm cram  core compressed-RAM tier API 
  APPLIED byte-identical.
- 084 mm  force copy-on-write for anon folios on a write-fenced no
  SKIP-FWD -> fwd/084-fwd-7.2.9-writefence-cow.patch
  why: same EOF-anchor reason as 082; cram.h include + folio_must_cow() placed before relocated node_placement_check(). Rest verbatim.
- 085 mm migrate  re-install migrated write-fenced folios read-onl
  SKIP-FWD -> fwd/085-fwd-7.2.9-migration-remap.patch
  why: 7.2.9 has uffd-wp API (pte_mkuffd_wp etc.) plus young/dirty preservation lines absent in branch base; mkwrite sites refreshed to _wp forms.
- 086 mm cram  demote anonymous folios onto the CRAM tier 
  SKIP-FWD -> fwd/086-fwd-7.2.9-cram-demote-anon.patch
  why: 7.2.9 shrink_folio_list() uses swap_iocb *plug where branch has 7.3-bound swap_io_ctx; hunk 1 context refreshed (same two insertions).
- 087 mm  map write-fenced folios read-only at fault time 
  SKIP-FWD -> fwd/087-fwd-7.2.9-fault-readonly.patch
  why: 7.2.9 set_pte_range tail uses pte_mkuffd_wp(); context refreshed to _wp form. Insertions verbatim.
- 088 mm mprotect  keep write-fenced folios read-only across mprot
  SKIP-FWD -> fwd/088-fwd-7.2.9-mprotect-wrfence.patch
  why: 7.2.9 uffd-wp API + vm_flags&VM_SHARED (predates VMA-flags refactor); 5 hunk contexts refreshed, logic verbatim.
- 089 mm migrate  keep write-fenced file folios read-only on migra
  SKIP-FWD -> fwd/089-fwd-7.2.9-migrate-wrfence.patch
  why: 7.2.9 lacks the uffd-rwp PAGE_NONE step used as anchor; guard anchored at device_private block instead. huge_memory hunk verbatim.
- 090 mm cram  promote a resident file folio off the tier on write
  APPLIED byte-identical.
- 091 mm filemap  serve reads of resident file folios in place 
  APPLIED byte-identical.
- 092 mm  drop resident file folios on truncate  backstop dirtying
  APPLIED byte-identical.
- 093 mm cram  demote clean file folios onto the CRAM tier 
  APPLIED byte-identical.
- 094 dax kmem  register compressed-RAM regions as a CRAM node 
  APPLIED byte-identical.
- 095 mm cram  add the  TEST  debugfs control interface 
  APPLIED byte-identical.
- 096 selftests dax  add the CRAM tier tests 
  APPLIED byte-identical.
- 097 selftests dax  add CRAM file-tier latency probe   fs-matrix 
  APPLIED byte-identical.
- 098 selftests dax  carry the generic tiering perf tooling 
  APPLIED byte-identical.
- 099 dax kmem  expose adistance on all kmem nodes  not just priva
  APPLIED byte-identical.
- 100 selftests dax  rework demotion subtest 2 to actually exercis
  APPLIED byte-identical.
- 101 selftests dax  fix tier latency refault to measure REAL swap
  APPLIED byte-identical.
- 102 mm filemap  drop CRAM folios on write 2  overwrite instead o
  APPLIED byte-identical.
- 103 selftests dax  add CRAM write 2 -drop adversarial test 
  APPLIED byte-identical.
- 018b (Saphira follow-up, no upstream counterpart)
  FWD -> fwd/018b-fwd-7.2.9-alloc-flags-order.patch
  why: fwd-018 placed ALLOC_DEFAULT/ALLOC_ZONELIST_PRIVATE next to the
  other ALLOC_* macros, ~800 lines below their first users
  (select_zonelist, struct alloc_context), breaking the 7.2.9-r1 build
  (mm/filemap.c, kernel/fork.c). Moves both defines above
  struct alloc_context. No semantic change.
- 016b (Saphira follow-up, no upstream counterpart)
  FWD -> fwd/016b-fwd-7.2.9-frozen-callsites.patch
  why: fwd-016 changed __alloc_frozen_pages_noprof() to 5 args but missed
  the two callers using the __alloc_frozen_pages() wrapper macro
  (mm/slub.c alloc_slab_page, mm/hugetlb.c hugetlb alloc), found via the
  7.2.9-r1 build log. Both pass ALLOC_DEFAULT. No semantic change.

# Structural compiler-speed work, 2026-11-05

This session follows the existing compiler profiles and the retained DevMode
campaign report. It uses structural evidence from the current implementation.
No elapsed-time, profiling, benchmark, or load-test run was made.

## Earlier retained batches

The campaign branch also merged the following work after the previous
compilation report:

| Area | Retained work | Compiler work removed |
| --- | --- | --- |
| Loop, SLP, MemToReg and post-RA state | Flattened register, label, relocation, induction, block-membership and nested-loop lookup tables; indexed selected loop candidates. | Repeated linear or nested-table searches and per-candidate container construction on optimizer paths. |
| LICM, spills and record promotion | Reused worklists, eligibility sets, spill reachability marks, candidate buffers and record-state storage; released converged filters and skipped empty state setup. | Repeated scratch allocation, initialization and scans across acceptance rounds or candidates. |
| Early analysis gates | Skipped empty-pass setup, label-dependent CFG work without labels, branch SSA without flag producers, and constant-fold scans without known values or constant addresses. | Pass setup and whole-function analysis when the required instruction shape or input facts are absent. |
| Shared instruction and relocation walks | Collected local-base definitions and copies in existing walks, reused instruction-stream scans for sink analysis, propagated upper halves linearly, and shared linker alias and relocation facts. | Duplicate instruction, CFG and relocation traversals for facts produced by the same input walk. |

The address-taken label list remains in instruction order. Binary search on that
unsorted list was rejected; membership checks keep their original semantics.

| Retained change | Compiler work removed | Equivalence argument | Validation |
| --- | --- | --- | --- |
| Index loop induction candidates | Repeatedly scanning the discovered induction list for each register candidate | A packed-register `FlatKeyMap` records each candidate's existing vector index. Candidate order and the selected induction are unchanged. | DevMode build; all 1,678 C++ tests passed. |
| Bound MemToReg frame-range queries | Scanning every known frame extent to answer containment and overlap queries | The extents are sorted and disjoint; `upper_bound` starts at the only possible containing range and visits only ranges intersecting the query. | DevMode build; all 1,678 C++ tests passed. |
| Index escaped MemToReg frame objects | Scanning all frame objects for each escaped offset | The same sorted, disjoint frame extents are searched by their upper bound, poisoning only the containing object as before. | DevMode build; all 1,678 C++ tests passed. |
| Defer BranchSimplify ordinal indexing | Filling an instruction-reference ordinal table for functions whose branch transforms never query ordinals | The table is built on the first ordinal query from the same ordered instruction references; queried ordinals retain their prior values. | DevMode build; all 1,678 C++ tests passed. |
| Reuse the SSA fixed-point result in constant folding | Scanning every known-value flag after propagation to determine whether any value was inferred | The fixed-point routine returns whether its unresolved count changed, which is equivalent to checking the final flags. | DevMode build; all 1,678 C++ tests passed. |
| Mark selected MemToReg promotions | Scanning the promotion list for each candidate vector slot | A flag on each slot is set from the final overlap-filtered promotion list; the lane split consults that same final selection. | DevMode build; all 1,678 C++ tests passed. |
| Index register-allocation reservations | Scanning every reserved physical-register range for each candidate overlap or local-allocation query | Ranges are inserted in start order only after an overlap check, so they remain disjoint; lower-bound queries find the first range that could intersect without changing the allocator's decisions. | DevMode build; all 1,678 C++ tests passed. |
| Index sealed loop-region lookup | Scanning all sealed loop regions at every label during register allocation | Regions are collected by increasing instruction index; `lower_bound` locates a label's header while preserving the exact region selected. | DevMode build; all 1,678 C++ tests passed. |
| Reuse register back-edge membership | Searching each active loop's back-edge list again while protecting expected register pairs | The membership result is refreshed for the current instruction during residency conformance and reused by the immediately following protection scan. | DevMode build; all 1,678 C++ tests passed. |

At the latest compiler-validation checkpoint, DevMode passed all 1,678 C++ tests
with one warning; 114 filesystem tests were skipped by the default suite
configuration. The changes are structural; no speed or memory improvement is
claimed without a benchmark.

# Structural compiler-speed work, 2026-11-05

This session follows the existing compiler profiles and the retained DevMode
campaign report. It uses structural evidence from the current implementation.
No elapsed-time, profiling, benchmark, or load-test run was made.

| Retained change | Compiler work removed | Equivalence argument | Validation |
| --- | --- | --- | --- |
| Index loop induction candidates | Repeatedly scanning the discovered induction list for each register candidate | A packed-register `FlatKeyMap` records each candidate's existing vector index. Candidate order and the selected induction are unchanged. | DevMode build; all 1,678 C++ tests passed. |
| Bound MemToReg frame-range queries | Scanning every known frame extent to answer containment and overlap queries | The extents are sorted and disjoint; `upper_bound` starts at the only possible containing range and visits only ranges intersecting the query. | DevMode build; all 1,678 C++ tests passed. |
| Index escaped MemToReg frame objects | Scanning all frame objects for each escaped offset | The same sorted, disjoint frame extents are searched by their upper bound, poisoning only the containing object as before. | DevMode build; all 1,678 C++ tests passed. |
| Defer BranchSimplify ordinal indexing | Filling an instruction-reference ordinal table for functions whose branch transforms never query ordinals | The table is built on the first ordinal query from the same ordered instruction references; queried ordinals retain their prior values. | DevMode build; all 1,678 C++ tests passed. |
| Reuse the SSA fixed-point result in constant folding | Scanning every known-value flag after propagation to determine whether any value was inferred | The fixed-point routine returns whether its unresolved count changed, which is equivalent to checking the final flags. | DevMode build; all 1,678 C++ tests passed. |
| Mark selected MemToReg promotions | Scanning the promotion list for each candidate vector slot | A flag on each slot is set from the final overlap-filtered promotion list; the lane split consults that same final selection. | DevMode build; all 1,678 C++ tests passed. |

The latest synchronized DevMode run passed all 1,678 C++ tests with one warning;
114 filesystem tests were skipped by the default suite configuration. The changes
are structural; no speed or memory improvement is claimed without a benchmark.

# Reuse unmodified private-global loads

Batch 18. Baseline: batch 17 (52c417e02). Candidate: 58959735b plus this
change, including concurrent compilation-speed work. Compiler and programs are
Release. No timing claim is made.

Value numbering now treats a private global as immutable within a call-free
function when no direct write overlaps the bytes read. The proof is computed
lazily, covers the entire function (including calls later on a back edge), and
rejects escaped/materialized global addresses, unsupported relocations and
unrelocated RIP writes. Existing SSA availability, dominance, relocation identity
and invalidation rules still apply. Arbitrary pointer stores and writes to
other global cells no longer force the same private cell to be read again.

| Function | Instructions before / after | Memory operations before / after |
| --- | --- | --- |
| Dijkstra.push | 27 / 25 | 16 / 14 |
| Dijkstra.pop | 43 / 39 | 28 / 24 |
| Dijkstra main | 424 / 424 | 163 / 163 |
| Total | 494 / 488 | 207 / 201 |

Explicit RSP accesses remain six and pushes seven, all in main. The sift-up loop
already used eight heap memory operations; these savings remove redundant global
reads at entry. The selected-child reload in pop remains compiler.optimization.034.
Normalized complete bodies and counts are retained beside this report.

Validation: the full native Release campaign passes 3,639 tests in JIT and native
execution, including expected recovery probes. The source regression covers
stores through pointers, disjoint globals, both branches and a later call that
mutates a global on the next iteration. Nine internal fixture variants cover
exact/partial overlap, adjacent ranges, calls, address materialization, non-private
cells and unrelocated writes; the Release compiler does not execute C++ fixtures.

ChaCha, nbody, CSV and all 334 H.264 bodies retain their instruction, memory,
RSP-access and push counts. Dijkstra, ChaCha, nbody and CSV checksums match their
references; `checksums.json` records them.

Integration: the later frontend metadata changes through 58beadf85 were imported
and rebuilt in Release; the focused optimizer and repository checks are repeated
on that combined tree. Counts and the full native campaign above describe the
58959735b snapshot, not a rerun of the complete campaign after that integration.

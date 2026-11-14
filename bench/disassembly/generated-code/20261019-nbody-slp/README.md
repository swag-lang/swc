# Independent double roots and mixed scalar/vector state

The benchmark sources, workload, timed boundaries and floating-point policy are unchanged.
The general SLP pass now captures shared scalar values at their definitions, snapshots inputs
before overlapping stores, and places each packed store at its original first write. Repeated
loads read only their scalar width. Scalar SSA names expose independent operations without
clobbering intervening values. Under the finite-value release policy, proven independent
square roots and divisions execute in pairs with exact hardware instructions.

Mixed scalar reads can consume a loop-carried packed frame chunk. A low-lane extraction
preserves the memory load's zero upper half; a high-lane extraction shifts by eight bytes.
The post-allocation lane analysis follows unpack, shuffle and byte-shift consumers before
removing a redundant clear. Constants stay after the entry allocation, preserving lightweight
prologues. Hoisting rejects unknown aliases, overlapping writes, observed upper halves,
live phi results, destructive consumers, calls, boundaries and unknown stack displacements.

| Native nbody timestep | Instructions | Memory operands | Roots | Divisions |
| --- | ---: | ---: | --- | --- |
| Accepted stable-local spill reuse | 396 | 163 | 10 scalar | 10 scalar |
| This batch | 390 | 145 | 5 packed | 5 packed |
| Zig comparator | 348 | 135 | 4 packed + 2 scalar | 4 packed + 2 scalar |

[Before](nbody-before.asm) and [after](nbody-after.asm) are actual x64 disassembly; counts omit
NOPs and comments and include the loop latch. Each packed instruction processes two doubles.
No reciprocal approximation or additional reassociation is introduced. All executions retain
checksum 169096566666.

The timestep executes 500,000 times: six fewer instructions and eighteen fewer memory operands
save 3,000,000 instructions and 9,000,000 memory operands. It also removes 2,500,000 square-root
and 2,500,000 division instructions. The full printed main grows 728/327 to 753/339 because its
once-executed code grows 31/30 while its timestep shrinks 6/18. Charging all that cold growth
once still saves 2,999,969 instructions and 8,999,970 memory operands. The standalone advance
body is not called by this fully inlined main. Energy runs once inside the timed region;
its inlined cost is already included in the cold-main accounting.

The [twelve-task comparison](microdiff.json) retains every checksum. After grouping generated
and overload ordinals, other task kernels and loops have no static loss. ChaCha main removes
two memory operations outside its unchanged 47-instruction double round. Two shared allocator
paths each lose one memory operation; their other counts are unchanged. No cold-only change
is used to justify accepting the batch.

Validation: 1,547 full C++ tests pass, including 24 independent-root proof variants, scalar-width
broadcasts, copy transparency, store ordering, entry allocation, mixed loop-state extraction,
and executed upper-lane comparisons before/after the peephole. Native Release passes 3,859
tests; JIT Release passes 1,539. Native recovery probes fail intentionally and the outer suite
returns success. Fresh output directories prevent reuse of old benchmark function artifacts.

The scalar exposure and upper-half propagation walk SSA definitions and uses. Root pairing
rebuilds SSA after each accepted pair, searches at most 4,096 instruction positions and clones
at most 256 pure input instructions per attempt. This is optional optimization work; those
bounds constrain compile cost, not accepted program semantics.

An exploratory 60-round pinned alternating panel of the same 390/145 timestep has median
candidate/baseline 0.9243 (range 0.8349..1.1556), candidate/Zig 1.1173 (1.0215..1.3038), with
unchanged Zig A/A 0.9963 (0.9428..1.1277). It preceded the cold-prologue placement repair.
These dispersed samples do not establish a final campaign speedup or a win over Zig. Acceptance
is based on the executed static reduction and checksums; the grouped Release campaign remains
the runtime verdict.

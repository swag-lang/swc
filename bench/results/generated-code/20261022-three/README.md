# CSV aggregation, nbody and sort

Prompt 2 starts at `2e8511af06`. The benchmark sources, workloads, checksums and
measured boundaries remain unchanged. DevMode compiler, Release benchmark programs.
Temporary installations, caches, listings and build outputs are outside the checkout.

## Overlapping dynamic comparison tails

`Swag.memcmp` compares the remaining range with a head and a tail of the largest
fitting scalar width. Both reads stay in the requested range; the head mismatch
wins when their ranges overlap. Exact-width ranges skip the redundant tail read.
Keeping the consumed offset rather than the original remaining length across the
head comparison avoids adding an integer clobber to this leaf's calling contract.

The equal-key paths in the emitted x64 code have these executed instruction and
memory-operand counts, including entry and return, excluding alignment NOPs:

| Key length | Before instructions | After instructions | Before reads | After reads |
| --- | ---: | ---: | ---: | ---: |
| 1 | 25 | 20 | 2 | 2 |
| 2 | 28 | 24 | 2 | 2 |
| 3 | 32 | 26 | 4 | 4 |
| 4 | 28 | 22 | 2 | 2 |
| 5 | 32 | 29 | 4 | 4 |
| 6 | 35 | 29 | 4 | 4 |
| 7 | 39 | 29 | 6 | 4 |

CSV's eight region strings have lengths 4, 4, 4, 5, 6, 6, 7 and 4. Its successful
comparison therefore saves an average 6.125 instructions and 0.25 memory operands
per row, about 2.45 million instructions and 100,000 reads over 400,000 rows. A
mismatch in the head retains its ordering and skips the overlapping tail.

All twelve Release benchmark checksums pass. Task kernels and their callers are
unchanged, including their saved registers and spills; only the shared dynamic
comparison body changes after overload ordinals and generated names are paired.
The vector loop retains its work. The six focused `memory_dynamic` tests pass
through JIT and native in DevMode, including all mismatch positions, unaligned
sizes through 65 bytes, and opposite-order mismatches in overlapping ranges.

A 24-round pinned alternating comparison of the final binaries is exploratory:
CSV candidate/base median 1.0418 with range 0.8181..1.7084 and unchanged A/A median
0.9721; wordfreq candidate/base median 0.9816 with range 0.7625..1.2412 and A/A
median 0.9866. These dispersed observations do not establish a speedup or a
reproducible slowdown. The batch is accepted on executed static work and remains
**landed, unconfirmed** until the grouped campaign.

## Dead floating clears

The physical-register lane-demand analysis now removes a clear only when no lane
of its result can reach an observation. Full definitions on every successor can
kill that demand; partial scalar copies, aliased arithmetic inputs, calls,
materialized control flow, claimed rewrites and unknown operations retain it.
Clear removal runs after floating memory folding so a pending erased lifetime
marker cannot obscure that sweep's reload fusion.

Nbody's actual native timestep changes from **390 to 375 instructions**, with
**145 memory operands**, five packed roots and five packed divisions unchanged.
It executes 500,000 times: the batch removes 7.5 million zeroing instructions,
without changing arithmetic, memory traffic, saved registers, spills or calls.
The full main changes 753/339 to 738/339 instructions/memory operands. The
out-of-line `advance`, unused by the fully inlined benchmark, loses one clear.
[Before](nbody-clear-base.asm) and [after](nbody-clear-new.asm) are emitted x64.

All twelve Release checksums pass. Other benchmark kernels and shared runtime
paths are unchanged after overload ordinals and generated names are paired.
The complete Micro comparison is in [clear-microdiff.txt](clear-microdiff.txt).
Correctness: 1,542 in-memory C++ tests pass, including executed vector-lane and
both-branch observations before/after optimization; 324 optimizer source tests
pass through JIT and native in Release with `--validate-micro`. The final compiler
has no temporary tracing instrumentation. Compiler build identity is unchanged.

The analysis uses the existing four-bit lane lattice over the CFG, restricted
to functions with unclaimed floating clears. This adds a candidate scan and one
lane-demand solve after memory folding; unsupported control flow declines it.
Timing is **not measured** for this batch; its runtime gain remains unconfirmed.

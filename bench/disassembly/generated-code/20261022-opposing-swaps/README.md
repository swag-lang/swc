# Opposing-index swap prefix peeling (2026-10-22)

Target: Fannkuch, last accepted competitive ratio 1.030 against Rust in
`20261022-103425.json`. Its short reversal updates two opposing indices, although
the left index always starts at a known constant and both indices die at exit.

The post-allocation pass peels the configured prefix using constant left addresses.
Each exchange retains the original four memory operations, their order and widths,
and the same physical registers. It removes the left-index increment. Every lane
checks the converging bound before another exchange. Long reversals resume a rotated
scalar tail with eight instructions per exchange. No disjoint-allocation assumption,
wide access, read-ahead, new call, spill, stack slot or register is introduced.
Live exit indices or flags, external header entries, address-taken labels, a moving
base, unsupported seeds and offsets, or insufficient configured growth all decline.

## Executed work

The final machine code changes the first four exchanges from **8 to 7 instructions
per exchange**, each retaining two reads and two writes. Entry changes from one
clear plus a compare/branch to just a compare/branch. For the actual N=9 workload,
k is 1..8, so all 1,911,505 reversals finish within four exchanges: the scalar tail
is cold. The source-order model reproduces checksum **8629030** and counts
4,536,603 exchanges. Entry and exchange work therefore falls from **42,027,339 to
35,579,231 executed instructions** (6,448,108 fewer; **15.34%** of this segment).
Both sides perform 18,146,412 memory accesses. Alignment NOPs and the unchanged
outer flip-update/reload are excluded. See the executable cost model and JSON;
this is instruction work, not measured elapsed speed.

## Correctness and regression boundary

All **1,562 C++ tests pass** after the final analysis-sharing change. The new cases
cover 38 eligibility graphs and 2,058 before/after executions: signed/unsigned
bounds, negative/nonzero seeds, lengths 0..48 and factors 2/3/4, including scalar
tails. Rejected forms cover live outputs/flags, alternate entries, wrong steps,
nonconstant/partial seeds, aliasing register roles, stack addressing, growth limits
and overflowing displacements. A second pass leaves the peeled result stable.

The Swag source fixture passes JIT and native in Release and guarded DevMode,
checking 3,136 array values per execution mode. All twelve Release benchmark
checksums match with the final Release compiler. The full verbose comparison is
retained. After pairing overloads and generated lambda names, **only Fannkuch's
main changes**; every other task kernel and reachable native runtime body remains
identical. Whole-function and outer-loop size increases are cold-prefix duplication,
not extra executed exchanges. Final disassembly confirms the per-exchange reduction.

The initializer search is bounded by the existing lookback. CFG physical-register
liveness and incoming-jump counts are computed lazily once per pass invocation;
flag-deadness queries visit successors only after an exact shape/seed match.
For P accepted loops in an N-instruction/E-edge function, repeated invocations
retain O(P*(N+E)) shared liveness work plus the candidate flag traversals. Emission
is O(F) for the configured factor. No analysis is run merely for a generic label.

Timing: **not measured** at acceptance; landed, unconfirmed. No benchmark source,
workload, checksum or timing boundary changed. The combined session campaign follows.

## Combined revision

The Release compiler rebuilt after integration at `2fa118f4af` passes the
full twelve-task comparison again. All checksums match; overload/lambda pairing
again isolates the changes to Fannkuch main. The integrated LZ77 scan stays intact.
Compiler SHA-256: `b2106d315fdf98b0587cc5a913ff7a96b4836b02eed209c8dd7b38883f5d4aca`.
The official campaign wrapper now accepts `--out` and forwards an absolute path
to preserve incomplete checkpoints. Its help, forwarding boundary and all 47
benchmark harness tests pass.

## Reuse the first exchange value

A bounded reverse-CFG proof now recognizes the first value already held in the
right-index register, on every path entering the prefix. It accepts an exact
64-bit load or store of that value and crosses only provably disjoint fixed
offsets through the same base. Calls, ambiguous/overlapping stores, changed
addresses or values, repeated CFG nodes, missing entry definitions and a live
first temporary decline. No allocation-disjointness assumption is introduced.
The query bounds each predecessor path to 32 instructions; its visited rows
are O(N) storage and work is at most O(N+E) per candidate. It runs only after
shape, offset, liveness and entry eligibility have succeeded.

Fannkuch's first exchange now has **6 instructions and 3 memory accesses**;
subsequent peeled exchanges retain 7 and 4. The final disassembly confirms
that the upper store directly uses the already available index value. This
removes one more instruction and read per reversal: **1,911,505** of each.
Combined entry/exchange work is **33,667,726 vs 42,027,339 instructions**
(**19.89% fewer**) and **16,234,907 vs 18,146,412 memory accesses**.
This is static executed work, not elapsed-time performance.

All 1,562 C++ tests pass, now covering 54 eligibility graphs and 6,174
before/after executions, including load/store availability, disjoint writes,
overlap rejection, changed values/bases and a live first temporary. The expanded
source fixture passes JIT/native Release and guarded DevMode (6,208 expected
array values per execution mode). The final Release compiler passes all twelve
checksums. Canonical pairing changes only Fannkuch main: 202 -> 201 instructions,
76 -> 75 memory accesses, unchanged nine calls and unchanged remaining kernels
and runtime. See `reuse-microdiff.txt` and `reuse-after.asm`.

Timing of this final complement: **not measured at acceptance**.

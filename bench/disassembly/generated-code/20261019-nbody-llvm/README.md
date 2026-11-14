# Why Zig's nbody timestep is smaller

Original sources, workloads and timed boundaries are unchanged. The accepted
20261018-194437 campaign measures Zig 17.1885 ms, Rust 21.0342, Swag native
Release 21.1719, Clang C++ 22.7218 and D/LDC 23.0192. These historical numbers
select the investigation; they are not timings of the scratch variants below.
Every scratch variant prints the original checksum, 169096566666.

| Actual native timestep | Instructions | Memory operands | Roots / divisions |
| --- | ---: | ---: | --- |
| Zig 0.15.2 | 348 | 135 | 4 packed + 2 scalar |
| Rust 1.97.1 | 448 | 215 | 3 packed + 4 scalar |
| Clang 20.1.8 C++ | 540 | 193 | 10 scalar |
| D/LDC 1.43.0 | 471 | 190 | 10 scalar |
| Swag after stable-local spill reuse | 396 | 163 | 10 scalar |
| C++, both interaction loops forced fully unrolled | 403 | 183 | 4 packed + 2 scalar |
| Same C++, SLP disabled | 525 | 159 | 10 scalar |
| D, only advance forced inline | 349 | 123 | 4 packed + 2 scalar |

Counts exclude NOP padding and include the loop latch. Clang's original four
inner loops execute 4, 3, 2 and 1 times per timestep; the table weights their
counts accordingly. D's original advance count includes its per-call prologue,
epilogue and return; the caller adds a small call loop. Packed operations work
on two double lanes, so all rows still perform ten interactions. A memory
operand count is not a byte count: packed operands transfer wider values.

The important distinction is the complete optimized loop shape. Zig inlines
advance, fully expands both nested interaction loops, folds the known masses
and keeps the simulation state in registers and private spill slots. This
exposes independent interactions to SLP, which groups roots/divisions and also
coordinates and velocity updates. It uses real SSE2 sqrt/div instructions,
with no reciprocal or approximate-root shortcut, FMA requirement or reduced
step count.

Clang's normal /O2 recipe inlines advance but leaves the four inner loops.
Correctly selecting O3 (/clang:-O3 under clang-cl), unsigned induction variables
and an array-reference parameter leave that shape unchanged. Hinting only the
inner loop with unroll(full) fails to transform it; hinting both nested loops
fully unrolls the whole interaction set and unlocks the packed shape. The
remaining instruction/memory gap shows that matching the root count alone does
not reproduce Zig's allocation and scheduling.

D's normal -O3 -release -boundscheck=off recipe leaves advance out of line.
Adding only pragma(inline, true) before its definition exposes the actual array
and constants to the optimizer and changes its timestep from 471/190 to
349/123, with the same packed-root shape as Zig. This isolates a frontend/
inlining/pass-order decision rather than a fundamental LLVM inability.
LDC reports LLVM 22.1.8; rustc reports LLVM 22.1.6; the installed Clang is 20.1.8
and Zig's bundled Clang reports 20.1.2. Sharing LLVM does not imply sharing its
input IR, inlining decisions, pass options or the final live ranges.

Two nine-round alternating, performance-core-pinned panels retain identical
Zig controls at the start/end of every round. The loaded panel's control ratio
ranges from 0.128 to 6.782 (median 1.192). A second panel started with low system
CPU but still ranges from 0.0472 to 1.6376 (median 0.8987). Neither supports a
quantitative speedup claim. All 117 executions in each panel retain the original
checksum. Static shape and checksum conclusions remain valid.

Swag follow-up: raising only the external configuration's memory-copy unroll
budget to 512 bytes, or the generic full-unroll trip budget to 32, does not change
nbody's final code. These diagnostic settings are not retained. Small isolated
SLP gather/broadcast changes also failed to improve the timestep and were
reverted. A built vector plan runs into a real alias barrier: its leaf load
would move after an earlier overlapping scalar velocity store. Removing that
barrier would be incorrect. Exposing state as scalar SSA values, or placing
packed calculations before their first overlapping store, remains the next
compiler mechanism to investigate.

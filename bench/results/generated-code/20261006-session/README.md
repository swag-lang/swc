# Optimization session, 2026-10-06

Fourteen code batches were validated and merged into local master in sequence,
from the separate perf/optimization-boundaries-20261006 worktree (the initial
VEX batch also used perf/optimization-until-noon-20261006). No remote push was
requested. SWC_BUILD_NUM remains 1173. The compiler and optimized programs used
for optimization validation are Release; script launchers may print their own
default devmode configuration, which is not a performance measurement.

| Batch | Retained change | Evidence |
| --- | --- | --- |
| 1 | Consistent VEX encoding for XMM operations, including high register/index bits | [AVX/VEX](../20261006-avx-vex/README.md) |
| 2 | Constant address folding and reverse narrow-select propagation | expectedCountOnes16: 20 to 6 pre-RA sweeps, same final instructions |
| 3 | Preserve SSA after removal of register reads | Fresh-analysis comparison; definitions and added reads retain full rebuild |
| 4 | Claim MUL's output-only RDX only at output | [Fixed claims](../20261006-mul-claims/README.md) |
| 5 | Remove the permanent GP legalization reserve | [Register allocation](../20261006-legalize-reserve/README.md) |
| 6 | Fold late single-use constant address bases into memory operands | [Late addresses](../20261006-late-addresses/README.md) |
| 7 | Carry adjacent loads/stores between loop iterations | [Loop forwarding](../20261006-loop-load-forward/README.md) |
| 8 | Reuse SSA dominance intervals in five analyses | [Dominance reuse](../../compiler-work/20261006-ssa-dominance/README.md) |
| 9 | Cache complex private integer spill homes in unused XMM registers | [Carried spills](../20261006-carried-spill-cache/README.md) |
| 10 | Borrow stable array arguments for eligible pure inline leaves | [Array borrowing](../20261006-inline-array-borrow/README.md) |
| 11 | Group two counted iterations with bounded code growth; cache write-only homes | [Partial unrolling](../20261006-partial-counted-unroll/README.md) |
| 12 | Cache read-only private homes across conditional calls and multiple entries | [Read-only caches](../20261006-private-read-cache/README.md) |
| 13 | Extend those caches to mutable homes with coherent existing stores | [Write-through caches](../20261006-private-write-through/README.md) |
| 14 | Pack indexed read-modify-write groups; reconcile moving-SP aliases | [Indexed SLP](../20261006-indexed-slp/README.md) |

Representative structural outcomes:

- The SHA-256 compression loop keeps all eight state values in registers. Two
  rounds execute 95 instructions, four data reads and no frame accesses, against
  100 instructions before grouping. Outer-loop frame costs remain tracked.
- Levenshtein's hot iteration goes from five memory operations to three, with
  no frame access. The extra outer-loop initialization cost remains tracked.
- Inflate's literal-path latch goes from four frame reloads to zero across the
  two call-aware cache batches. Whole-function growth is documented separately.
- The same 334 H.264 bodies go from 44,274 instructions / 10,296 memory operations /
  2,538 explicit RSP accesses before reserve removal to 44,014 / 9,940 / 2,189 in
  the final dump. This endpoint comparison includes concurrent master updates;
  individual batch records provide closer attribution. It is not a runtime result.

The latest complete native Release run passes 3,638 tests in JIT and native
execution plus expected recovery probes; 21 compression and 23 H.264 tests pass.
Earlier selected validation also covered HEVC and the seven benchmark checksums.
After integrating concurrent master work, Release rebuilds succeed and the new
cold-call regression passes again. Internal C++ fixtures were added where useful,
but the late Release-only rounds do not execute them. No final timing campaign
was run on the occupied shared machine; static improvements stand on emitted
code and correctness coverage, not noisy timing significance.

## Retired CABAC diagnosis

The five current Slice.residualCabac instances have no frame accesses anywhere
in the source-annotated significance region, including hit and refill arms.
The normalized excerpts in cabac-significance.micro retain that observation.
The old two-latch-reload diagnosis in compiler.optimization.103 is therefore
retired. This is a rebaseline, not an additional gain attributed to batch 13.
The region already had no frame accesses immediately after reserve removal.
Remaining serial decoder work continues in std.video.001.

## Remaining local allocation costs

The two exceptions tracked in compiler.optimization.035 still exist in the final
cohort. Against the pre-reserve-removal baseline, parsePlaneResidualCabac changes
from 357 instructions / 100 memory operations / 40 explicit RSP accesses / six
pushes to 355 / 101 / 41 / seven. parsePlaneResidualCavlc changes from 397 / 99 /
41 / six to 410 / 105 / 47 / seven. Their normalized instruction diffs are retained
here for the next live-interval investigation. No timing regression is inferred.
The extra general-purpose register remains available globally; these individual
allocation choices remain unfinished work, not grounds to restore the reserve.

The afternoon indexed-SLP batch reduces ChaCha main from 446 instructions / 143
memory operations to 425 / 113. Its necessary moving-SP alias repair is included,
with a reduced regression that fails before the repair and passes afterwards.
Nbody saves five instructions and four memory operations; the H.264 panel has a
net increase of one instruction and two memory operations, detailed in batch 14.

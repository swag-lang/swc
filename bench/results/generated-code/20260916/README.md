# Generated-code audit - 2026-09-16

This session uses the separate `swc-micro-release` worktree and Release
`swc.exe`, with `-bc release` and six workers. Each validated optimization batch
was merged into local master. The persisted corpus checkpoint records measured
builds 829 (376fe9e1c) and 830 (e6e9d1623), identified separately for each
corpus. Focused continuation measurements through build 969 are
recorded below.

## Machine-code measurements

Matching Swag and C++ functions retain the same parameter layout. Swag
canonicalizes narrow signed returns to 64 bits, so some signed 32-bit results
retain an extension that the C++ return convention does not require.
The reference compiler is clang 21.1.6 with
`-O2 -target x86_64-pc-windows-msvc`. Counts include RET and exclude trailing alignment
and runtime functions. Internal padding before the last RET is retained. Ten-byte MOVABS instructions are counted in full.

The six corpora were introduced at different times. Each has its own baseline;
percentage reductions must be calculated within that corpus.

| Corpus | Functions | Baseline build | Baseline bytes | Measured build | Measured bytes | LLVM bytes |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| [Initial](counts.csv) | 51 | 688 | 994 | 830 | 540 | 559 |
| [Additional](additional/counts.csv) | 25 | 740 | 412 | 830 | 335 | 346 |
| [Third](round3/counts.csv) | 32 | 759 | 516 | 829 | 410 | 416 |
| [Fourth](round4/counts.csv) | 32 | 794 | 440 | 829 | 364 | 385 |
| [Memory and loops](round5/counts.csv) | 16 | 809 | 195 | 829 | 170 | 259 |
| [Extracted bits](extracted-bits/counts.csv) | 14 | 827 | 185 | 829 | 149 | 172 |

The corpora contain 170 functions. No function grows against its own baseline.
The initial corpus reduces bytes by 45.7% and instructions from 319 to 191
(LLVM: 192). Forty-nine functions shrink, two retain their size, and none grows.
Forty-four match LLVM's size and seven are smaller. The additional corpus
also has no remaining larger function: nineteen match and six are smaller.
Six functions across the third, fourth and fifth corpora remain larger than
LLVM: one, four and one respectively.
All fourteen extracted-bit functions match or beat LLVM's size; eleven shrink
against their build-827 baseline and three retain their size.

The final continuation compared 18 additional scalar/indexed functions in one
round, then isolated five immediate updates, four sparse bitwise updates, five
constant shifts, four unary updates, four register comparisons, three variable
shifts and two multiplications. The initial 18 all match LLVM. The later 27 also
all match LLVM after the corresponding
batch; aggregate byte counts below use each round's pre-batch build as its own
baseline.

| Builds | Shape | Functions | Baseline bytes | Final bytes | LLVM bytes |
| --- | --- | ---: | ---: | ---: | ---: |
| 864 | Indexed increment | 1 | 13 | 5 | 5 |
| 865 | Indexed load/select | 1 | 17 | 12 | 12 |
| 866 | Indexed immediate updates | 5 | 58 | 30 | 30 |
| 867 | Sparse indexed OR/XOR | 4 | 42 | 22 | 22 |
| 868 | Indexed constant shifts | 5 | 57 | 26 | 26 |
| 869 | Indexed NOT/NEG | 4 | 42 | 18 | 18 |
| 870–871 | Indexed register comparisons | 4 | 54 | 40 | 40 |
| 874 | Indexed variable shifts | 3 | 54 | 32 | 32 |
| 875 | Indexed multiplication | 2 | 24 | 20 | 20 |

Seven later exploratory rounds added 70 small scalar functions. They cover bit
counts, power-of-two tests, min/max/clamp chains, median-of-three selections,
overflow-safe averages, saturating arithmetic, rotates, narrow signed returns
and byte/word result handling. Through round 24, the measured Swag total is
smaller than LLVM in three rounds and equal in one. The other two round totals
are larger only because Swag canonicalizes signed `s32` returns. The only other
larger function there is the `u16` median-of-three at 46 bytes versus LLVM's 45.
Round 25 deliberately probes branch-heavy `u8` expressions and records the
remaining gaps for later work.

| Round | Measured build | Functions | Swag bytes | LLVM bytes | Larger / equal / smaller |
| --- | ---: | ---: | ---: | ---: | ---: |
| 19 | 900 | 12 | 160 | 262 | 0 / 8 / 4 |
| 20 | 903 | 10 | 221 | 221 | 0 / 10 / 0 |
| 21 | 906 | 10 | 249 | 258 | 0 / 6 / 4 |
| 22 | 918 | 9 | 268 | 263 | 2 / 7 / 0 |
| 23 | 919 | 11 | 272 | 268 | 4 / 4 / 3 |
| 24 | 927 | 10 | 213 | 215 | 1 / 7 / 2 |
| 25 | 931 | 8 | 232 | 191 | 4 / 3 / 1 |

Five continuation rounds then concentrated on conditional code, narrow values
and indexed byte arithmetic. The table uses the last measured build for each
round. Round 26's sole larger function is `choose_between_u32`; its decision
body now matches LLVM, while its fifth argument still causes a stack frame.
Every function in rounds 27--29 matches or beats LLVM.

| Round | Measured build | Functions | Swag bytes | LLVM bytes | Larger / equal / smaller |
| --- | ---: | ---: | ---: | ---: | ---: |
| 25 | 959 | 8 | 244 | 191 | 6 / 0 / 2 |
| 26 | 969 | 16 | 199 | 201 | 1 / 10 / 5 |
| 27 | 959 | 18 | 229 | 233 | 0 / 15 / 3 |
| 28 | 959 | 14 | 180 | 192 | 0 / 11 / 3 |
| 29 | 959 | 16 | 220 | 235 | 0 / 11 / 5 |

Notable measured results include paired range guards at 17 bytes (equal to
LLVM), conditional signed 64-bit shifts at 13 bytes (LLVM 16), conditional
`u8` multiplication at 17 bytes (equal), conditional `u8` left shift at 15
bytes (LLVM 20), and all four common `u16` arithmetic forms equal to LLVM.
The range-guarded `u32` value select falls from 34 to 30 bytes: its two-compare,
two-`cmov` body matches LLVM, with the remaining 12-byte difference coming from
Swag's frame setup and teardown around the fifth stack argument.
The late indexed-byte follow-up reduces floor average from 22 to 14 bytes
(LLVM 16), ceiling average from 22 to 17 (LLVM 16), and saturating add from 24
to 19 (LLVM 20).

Notable late reductions include unsigned and signed `median3` chains, repeated
comparison reuse, direct narrow conditional results, and widened overflow-safe
averages. Unsigned `median3` is 37 bytes versus LLVM's 39; signed floor and
ceiling averages are 16/16 and 19/19; saturating unsigned add and subtract are
19/19 and 15/15. The signed clamp is 21 bytes versus LLVM's 18 solely because
of its final three-byte `movsxd`.

The narrow-result continuation reduces `u16` floor and ceiling averages from
28 bytes to 14 and 16, saturating add from 31 to 21, saturating subtract from
21 to 17, absolute difference from 25 to 21, and median-of-three from 60 to
46. Rotations, byte swaps and three-value min/max chains now match LLVM.
The `u8` saturating-add follow-up reduces 29 bytes to 22; LLVM emits 20.
Two supplementary `u8` probes isolate the larger branch-heavy gaps: spelling
the loaded operands once as locals reduces saturating subtract from 32 to 18
bytes (LLVM 19) and absolute difference from 46 to 19 (LLVM 22). Future work
there should target repeated memory-expression reuse and branch formation,
rather than the final post-allocation sequences.

These are static measurements of examples selected during optimization, not a
representative workload average or a runtime speed claim. A smaller hardware
IDIV sequence, for example, need not execute faster than a longer multiplication
sequence. LLVM vectorizes `loadSum4` and `accumulate` in the fifth corpus;
Swag emits smaller scalar bodies, which does not establish a throughput advantage.
Checkpoint comparisons include concurrent changes integrated from
`master`, not only changes authored in this worktree.

Each directory contains matching Swag/C++ inputs, per-instruction assembly,
CSV/JSON counts, and compiler/artifact hashes in `identity.json`.

| Example | Corpus baseline bytes | Measured bytes | LLVM bytes |
| --- | ---: | ---: | ---: |
| `(a & b) | (a & c)` | 25 | 10 | 10 |
| `a | (a & b)` | 16 | 4 | 4 |
| `(a & 255) | (a & 65280)` | 21 | 4 | 4 |
| `(a & c) | (b & ~c)` | 25 | 13 | 13 |
| `a * (b + 1) - a * b` | 19 | 4 | 4 |
| Signed `a % 8` | 32 | 22 | 22 |
| `a ^ (a | b)` | 13 | 10 | 10 |
| `a == 0 ? ~0 : 0` | 12 | 10 | 10 |
| `a != 0 ? ~0 : 0` | 12 | 9 | 9 |
| 32-bit `(a + b) * (a + b)` | 9 | 7 | 7 |
| Variable 64-bit rotate | 31 | 9 | 9 |
| `(a | b) - (a & b)` | 13 | 7 | 7 |
| Signed absolute-value selection | 14 | 11 | 11 |
| `a & (a - 1)` | 11 | 8 | 8 |
| 32-bit `a << (b & 31)` | 11 | 6 | 7 |
| Indexed signed 16-bit load plus a value | 12 | 9 | 9 |
| Extract byte 2 from a loaded 64-bit word | 10 | 5 | 5 |
| Memory comparison selecting a value or zero | 16 | 10 | 10 |
| Memory bit test selecting one of two values | 14 | 11 | 11 |
| 64-bit product from bit 31 | 14 | 9 | 11 |
| 32-bit product from bit 7 | 12 | 8 | 9 |

## Changes

The validated batches cover bitwise factoring and cancellation; constant masks
and selections; integer multiplication and division; direct signed power-of-two
remainders; address/base differences; width and sign-bit handling; high-byte
extraction; carry arithmetic; physical copy coalescing; and constant/variable
rotations. Later batches simplify negation and complementary sums, forward
copies into three-operand shifts, fuse signed indexed loads, read narrow memory
extracts directly, select values after memory comparisons, and emit register or
memory TEST for dead masked results. Zero initialization uses CFG liveness and
shorter x64 encodings. Recent batches factor implicit unit terms such as
`a * b + a`, fold repeated loads into multiplication, emit true 32-bit LEA results,
and select products directly from individual source bits. Typed TEST operands
participate in demanded-bit analysis so unnecessary extensions disappear.
The final batches add direct indexed memory encodings for increment/decrement,
immediate arithmetic and bitwise updates, sparse-width OR/XOR, constant shifts,
NOT/NEG and comparisons against registers. A post-allocation rewrite restores a
coalesced comparison source so 32-bit SETcc results can be cleared before the
comparison instead of zero-extended afterward.
Variable indexed shifts now encode their memory destination directly while the
legalizer moves an address away from the required `CL` register. Indexed
multiplication reuses a dead multiplier as the `imul reg,mem` destination.
The final integrated legalizer copies the indexed instruction operands before
inserting those moves, since insertion can grow and relocate operand storage.

Rewrites retain width, flags, SSA value identity, physical liveness, ABI and
encoding constraints. In particular, RET alone does not prove a physical value
dead, and changing a 32-bit definition must preserve its zero-extended result.

A reduced mask example exposed incorrect inference for wide integer branches.
A broader run caught an initial correction that also narrowed floating literals;
the final correction preserves their f64 inference contract. Another broad JIT
run caught instruction-index invalidation during post-RA dead-code removal.
Deferring erasures until analysis completes fixed it before that batch was merged.

## Validation

Builds and tests used CPU/memory admission and six workers. Focused tests rotated
between arithmetic, widths, flags, calls, branches, loops and register pressure,
plus selected core, pixel, UTF-8, hashing and crypto consumers. Native regression
files accompany optimization families under `bin/unittests/native/optimizer`.

Recent broader checks passed all 1,487 JIT tests at build 827, all 742 core tests
at build 818, all 3,338 native tests plus the three expected-failure recovery
probes at build 829, and all 3,376 native tests plus the three expected-failure
recovery probes at build 869. Build 830 passed four integration files covering
extracted bits, aggregate construction, floating fields and short-circuit
booleans. Each later batch used a different focused optimizer context; build
871 additionally passed indexed register comparisons and the independent
zero-extended boolean comparison test. Each batch was validated before its
merge into local master.

After the final two batches, build 875 passed all 3,379 native tests and the
three expected-failure recovery probes. Build 877 then rebuilt the combined
compiler, passed both indexed variable-shift and multiplication tests, and
preserved LLVM-equal code sizes for all five functions in that final corpus.
The final integrated binary also passed the indexed-register and independent
zero-extended boolean comparison tests, plus the repository integrity check.

Build 900 passed all 3,398 native tests. Build 919 passed all 3,411 native tests
plus the three expected-failure recovery probes after the later comparison,
selection, average and saturation batches. Focused Release tests rotated among
bit counts, address arithmetic, selection chains, signed and unsigned averages,
saturating arithmetic, data integrity and the concurrent division changes.
Build 927 passed all 3,418 native tests plus the same three recovery probes.
After rejecting an unsafe follow-up during exploration, the focused Release
GUI campaign also passed all 85 tests, including the HTML view cases that had
exposed the attempted regression.

Build 945 passed all 3,423 native tests plus the three expected recovery
failures. After the guard, conditional-operation, shift, multiplication,
indexed-average and saturating-add batches, build 959 passed all 3,432 native
tests plus the same three expected recovery failures. Build 964's guarded-select
batch passed 985 C++ tests, all 3,433 native tests and the same recovery probes.
Focused validation varied between branch diamonds, short-circuit booleans,
count boundaries, narrow return copies, implicit multiplication, carry handling
and indexed averages; the final repository integrity check also passed.

Builds 864–871 measured between 1.90 and 3.47 seconds and 314.62 to 328.32 MiB
peak working set. Builds 874 and 875 measured 10.02 and 30.78 seconds under
heavier concurrent load, at 310.33 and 303.89 MiB. Shared-machine variation is
larger than these differences, so they are admission and regression evidence
rather than a claimed speedup.

The full repository campaign, DevMode compiler and C++ unit tests were not run
by this worktree during this session. Concurrent contributors performed separate
checks on their changes; those do not constitute a global checkpoint campaign.
Shared-machine timing varied enough that no compile-time speedup is asserted.

## Reproduce

Run the repository load admission check before each compilation. Use an external
scratch directory for libraries, objects, extraction files and compiler copies.

```powershell
& <compiler>/swc.exe build -f <report>/scalars.swg -ak static-library -n scalars `
  -bc release --num-cores 6 --out-dir <scratch>/out --work-dir <scratch>/work
clang -O2 -c -target x86_64-pc-windows-msvc <report>/scalars.cpp -o <scratch>/scalars.obj
llvm-objdump -d --x86-asm-syntax=intel <scratch>/scalars.obj
```

Use each subdirectory's corresponding source pair for the later corpora. Extract
COFF members before disassembling Swag libraries: LLVM's archive reader rejects
the current Swag long-name table (`compiler.core.050`). Counted instruction byte
sizes are preserved in each `counts.json` and `assembly.txt`.

## Closed scalar leads

The retained build-815 gaps were remeasured at build 869. `bitTimesValue`,
`divideAndRemainder`, `loadRepeated` and `selectLoad` now match LLVM.
`negativeModuloTwo` and `unsignedModulo32` are smaller than LLVM. The only size
difference in `signedModulo32` (19/16 bytes) and `signedDivide32` (30/27 bytes)
is the required three-byte signed-return extension from the Swag ABI contract.
The continuation therefore leaves no unexplained larger function among those
recorded scalar and memory leads.

## Intermittent diagnostic retained for follow-up

Build 728 diagnosed twelve null dereferences in
`native/inline/binding_visit_growth.swg`. Older binaries differed depending on
scratch roots or source location, and later repeated attempts did not reproduce
it. Temporary tracing was removed; multiple subsequent full native suites,
including build 799, pass. This does not establish the original cause.
`compiler.core.052` remains open; the failure is not claimed fixed.

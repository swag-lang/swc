# Generated-code audit - 2026-09-16

This session uses the separate `swc-micro-release` worktree and Release
`swc.exe`, with `-bc release` and six workers. Each validated optimization batch
was merged into local master. The persisted corpus checkpoint records measured
builds 829 (376fe9e1c) and 830 (e6e9d1623), identified separately for each
corpus. Focused continuation measurements through build 877 (41b8144f5) are
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

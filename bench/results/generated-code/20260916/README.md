# Generated-code audit - 2026-09-16

This ongoing session uses the separate `swc-micro-release` worktree and Release
`swc.exe`, with `-bc release` and six workers. Each validated optimization batch
is merged into local `master`. This checkpoint records build 815 at
`7a1cf7cf7`; iteration continues after it.

## Machine-code measurements

Matching Swag and C++ functions retain the same three-argument layout. Swag
canonicalizes narrow signed returns to 64 bits, so some signed 32-bit results
retain an extension that the C++ return convention does not require.
The reference compiler is clang 21.1.6 with
`-O2 -target x86_64-pc-windows-msvc`. Counts include RET and exclude trailing alignment
and runtime functions. Internal padding before the last RET is retained. Ten-byte MOVABS instructions are counted in full.

The five corpora were introduced at different times. Each has its own baseline;
percentage reductions must be calculated within that corpus.

| Corpus | Functions | Baseline build | Baseline bytes | Build 815 bytes | LLVM bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| [Initial](counts.csv) | 51 | 688 | 994 | 540 | 559 |
| [Additional](additional/counts.csv) | 25 | 740 | 412 | 335 | 346 |
| [Third](round3/counts.csv) | 32 | 759 | 516 | 412 | 416 |
| [Fourth](round4/counts.csv) | 32 | 794 | 440 | 364 | 385 |
| [Memory and loops](round5/counts.csv) | 16 | 809 | 195 | 172 | 259 |

The initial corpus reduces bytes by 45.7% and instructions from 319 to 191
(LLVM: 192). Forty-nine functions shrink, two retain their size, and none grows.
Forty-four now match LLVM's size and seven are smaller. The additional corpus
also has no remaining larger function: nineteen match and six are smaller.
The third, fourth and fifth corpora retain two, four and two larger functions
respectively.
No function grows against its own baseline in any of these corpora.

These are static measurements of examples selected during optimization, not a
representative workload average or a runtime speed claim. A smaller hardware
IDIV sequence, for example, need not execute faster than a longer multiplication
sequence. LLVM vectorizes `loadSum4` and `accumulate` in the fifth corpus;
Swag emits smaller scalar bodies, which does not establish a throughput advantage.
Checkpoint comparisons include concurrent changes integrated from
`master`, not only changes authored in this worktree.

Each directory contains matching Swag/C++ inputs, per-instruction assembly,
CSV/JSON counts, and compiler/artifact hashes in `identity.json`.

| Example | Corpus baseline bytes | Build 815 bytes | LLVM bytes |
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

## Changes

The validated batches cover bitwise factoring and cancellation; constant masks
and selections; integer multiplication and division; direct signed power-of-two
remainders; address/base differences; width and sign-bit handling; high-byte
extraction; carry arithmetic; physical copy coalescing; and constant/variable
rotations. Later batches simplify negation and complementary sums, forward
copies into three-operand shifts, fuse signed indexed loads, read narrow memory
extracts directly, select values after memory comparisons, and emit register or
memory TEST for dead masked results. Zero initialization uses CFG liveness and
shorter x64 encodings.

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

Recent broader checks passed all 1,487 JIT tests at build 812, all 742 core tests
at build 796, and all 3,328 native tests plus the three expected-failure recovery
probes at build 815. The intervening batches rotated focused files and selected
consumers, including thirteen core hashtable tests at build 813. Each batch was
validated before its merge into local master.

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

## Remaining leads

`compiler.optimization.041` tracks the current larger cases. They include absolute
value and bit selection, `(a | b) - (a & b)`, combined quotient/remainder,
zero-minus and complemented arithmetic, and several 32-bit register/width choices.
The previously recorded initial-corpus gaps have all reached or beaten LLVM size.

## Intermittent diagnostic retained for follow-up

Build 728 diagnosed twelve null dereferences in
`native/inline/binding_visit_growth.swg`. Older binaries differed depending on
scratch roots or source location, and later repeated attempts did not reproduce
it. Temporary tracing was removed; multiple subsequent full native suites,
including build 799, pass. This does not establish the original cause.
`compiler.core.052` remains open; the failure is not claimed fixed.

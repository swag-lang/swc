# Generated-code static audit - 2026-09-14

Campaign 1 is verified with DevMode compiler build 597. All 18 functions
across the seven benchmarks retain their baseline instruction and memory counts.
This correctness campaign does not establish a performance improvement. No benchmark
executable was run and no runtime timing or speed ratio was measured.

The isolated worktree is `swc-generated-code-sept14`, branch
`perf/generated-code-sept14`. The baseline is commit `b3ae86a4a`, DevMode
compiler build 590. Swag benchmark programs use `release`; unchanged C++
benchmarks use clang-cl 20.1.8 with `/O2 /EHsc /std:c++20 /FA /c`.
[Input and output hashes](identity.json) identify the observations.

## Baseline loop shapes

| Loop | Swag micro instructions / memory operations | clang-cl native instructions / memory operations |
| --- | ---: | ---: |
| SHA-256 compression round | 72 / 5 | 74 / 5 |
| Leven dynamic programming | 22 / 5 | 16 / 3 |
| Dijkstra heap sift-up | 26 / 15 | 16 / 8 |
| Raytrace pixel | 52 / 6 | 46 / 6 |

Counts exclude labels and include the terminating backward branch. Explicit
memory operands count as memory operations; LEA and implicit call-stack traffic
do not. Nested loop spans are never summed. Micro instructions and native
instructions describe different representations: this table does not establish
relative runtime performance. The complete [static census](loop-counts.json)
covers all seven tasks. Selected [Swag](swag-baseline-excerpts.txt) and
[clang-cl](clang-excerpts.txt) excerpts retain the exact counted spans.

The Leven reference retains two values across iterations that Swag reloads:
the previous `row0[y + 1]` supplies the next `row0[y]`, and the previous
`row1[y + 1]` result supplies the next `row1[y]`. SHA-256 contains complementary
shift/OR expressions that may admit rotate instructions when source width and
flag dependencies are proved. These are leads from the static audit.

## Campaign 1 and verification

Campaign 1 repairs flag-liveness checks across jumps and partial
flag writers, arithmetic reassociation with intermediate flag readers,
frame-address alias tracking during register promotion, and contextual enum
array indices. Compiler and source regressions accompany these changes.
The two Swag benchmark preludes also drop a redundant `ptr!` after the null
guard in `benchFree`. This removes the observed warning without changing the
algorithm. The baseline hashes retain the original prelude; the campaign hashes
record this one source difference explicitly.
Validation completed with the checkout-local DevMode 597 compiler and at most
six workers: 846 C++ tests with `unittest --dev-full`; both focused native enum
regressions; the focused invalid-index diagnostic; the full native suite
(3,168 tests, including its expected-failure recovery probes); and both full
semantic input sets (279 valid-source files and 294 expected-error files,
including compiler runtime inputs). All selected commands exited successfully.
The seven benchmark programs were built in `release` and never executed.

The user waived memory admission margins during this session. Fresh CPU
admission checks and the six-worker bound remained active.

The initial negative C++ run passed 797 cases and failed the four new regressions
for intermediate arithmetic flags, flags across jumps, overflowing shift counts,
and PostRA compare preservation. A subsequent intermediate build passed all 801
internal cases. A fuller intermediate run passed 838 cases but the linked native
test `Linker_NativeTestsDiscardRejectedCallees` did not complete successfully.
These runs preceded the final frame-alias and partial-flag corrections.

Inspection of the stalled core initializer and the reduced enum loop located a
register-promotion error: a frame pointer adjusted to another local slot could
leave the stores in memory while promoting the corresponding loads. The loop
index then became constant. The reduced source also exposed a semantic crash
when an enum-indexed array used `.First` inside a call argument. Both findings
are fixed and their permanent regressions pass. The rebuilt core initializer
also completes through the standard tool entry point.

## Reproduction

Preserve the baseline compiler outside every checkout. Copy benchmark sources
to an external temporary directory and prepend
`#global #[Swag.PrintMicro("post-emit")]` to each task's source. Build each task
with the checkout-local compiler, the task and common sources, and `bytemap.swg`
for CSV aggregation and Wordfreq:

```text
bin/swc.dm.exe build --num-cores 6 --build-cfg release -n <task> -od <out> -wd <out> -f <common-copy> -f <task-copy> [-f <bytemap-copy>]
```

Do not execute the resulting benchmark programs. Strip ANSI escapes, reset the
instruction-reference map at each function, and count each selected backward
branch span from its target label through the branch. Build C++ sources to
assembly/object files only with the flags above and separate `/Fa` and `/Fo`
paths. Every new compiler invocation must first pass the CPU admission check;
memory margins were explicitly waived by the user for this session.

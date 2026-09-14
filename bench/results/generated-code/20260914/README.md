# Generated-code static audit - 2026-09-14

Candidate validation is pending. This record currently contains the baseline
and C++ reference, not a verified performance improvement. No benchmark
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

## Candidate and verification

The current candidate repairs flag-liveness checks across jumps and partial
flag writers, arithmetic reassociation with intermediate flag readers,
frame-address alias tracking during register promotion, and contextual enum
array indices. Compiler and source regressions accompany these changes.
The integrated candidate has not yet passed its selected validations, so it
has not been merged into master and no subsequent campaign has started.

The shared machine's memory admission check currently prevents the final build
and tests. Earlier intermediate checks are not treated as validation of this
candidate. The required next checks are the DevMode compiler build, C++ tests,
focused native and semantic regressions, the native suite, and final static
dumps of the seven release benchmark programs.

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
paths. Every new compiler invocation must first pass the repository's current
machine-load admission check.

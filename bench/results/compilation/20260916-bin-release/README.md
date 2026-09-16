# Release compilation iterations, 2026-09-16

Work is isolated in `perf/bin-release-20260916`. Compilation measurements use the Release
`swc.exe`, program configuration `release`, forced rebuilds, and at most six workers. Each
command passes the repository CPU/memory admission guard; measurements use its stricter 20%
CPU threshold. Global validation is deferred at the owner's request. Contextual tests rotate
between batches while retaining the boundary directly affected by each change.

## Batch 1: JIT membership

The union of JIT roots uses the existing flat `PointerSet` instead of allocating an unordered-set
node per function. Constant-root discovery checks existing membership before rereading a known
function's eligibility. The discovery vector still controls order; macro/mixin exclusion,
optional-root validation and cache invalidation are unchanged. The temporary set remains local.

The isolated integrated comparison is master `83e124a50` (build 696), versus that revision plus
this batch (build 697). Both are normal Release builds. SHA-256:

- Baseline: `eb6bd3701eb93c5a77ed42795286227982afb0de67e6734f1e2af72b82d34728`.
- Candidate: `d9c851ee8f5de5d84c40e7f0bfa263830d456a4e3be197b3c16bf419807965fb`.

Command: `swc.exe build -w bin/std -m gui -bc release --num-cores 6 --rebuild --log-ascii`.
This rebuilds eight modules. A/B, B/A, A/B runs use the same six performance cores, selected by
`bench/winproc.py`. The harness records process CPU time, wall time and peak working set; an
external extension also records `QueryProcessCycleTime`. [Every sample](samples.csv) is retained.

| Paired change, median of three | Result |
| --- | ---: |
| Elapsed time | +1.73% |
| Process CPU time | -0.02% |
| Process cycles | -1.95% |

These measurements do not establish an end-to-end speedup. Shared-machine activity and run-to-run
variation exceed the expected small gain. The change removes per-function allocations locally;
no broad compilation-time percentage is claimed. An earlier one-worker sampling profile attributed
2.88% of sampled CPU to unordered-set insertion on the preparation stack; after the container
replacement that stack no longer performs unordered-set insertion. Those profiles used different
compiler revisions and are attribution evidence, not a controlled speed comparison.

Focused validation:

- Container replacement: DevMode compiler, program `devmode`, JIT suite: 1,487 passed.
- Final local code: DevMode JIT `--file-filter dynamic`: 52 passed.
- Final local code: Release compiler, program `release`, native `--file-filter reflection`:
  41 passed in JIT and in the emitted executable.
- After master integration: DevMode JIT `--file-filter global_function_ptr.swg`: one passed;
  six successful Release gui dependency-closure rebuilds in the paired measurement.
- Repository backlog validator passed. Both compiler configurations built successfully.

The CSV also preserves preliminary build-692/693 comparisons (`jit-flat-ab`, `jit-flat-serial`)
before the eligibility short-circuit and latest master integration. The serial experiment pinned
one performance core; it is a diagnostic control, not the intended parallel workload.

## Discarded: copy-elimination liveness

Two variants removed the internal SSA rebuild, first by scanning readers and then by adjusting
instruction-use counts and propagating phi liveness. The extra bookkeeping did not resolve a
compilation-time improvement: the count variant's three paired gui runs used 232.938 seconds of
baseline CPU versus 233.938 seconds for the candidate. Both implementations were discarded.

Both passed 825 C++ tests, including three experimental graph/liveness cases. The first also
preserved 16 normalized final Micro functions across Levenshtein and ChaCha, and passed 29 native
optimizer tests. A broader native run reached the existing release type-pattern failure after
3,248 successes; the unchanged build-688 baseline reproduces it in isolation. It was tracked by
`compiler.core.049`, resolved separately by `69f480e61`. The remaining SSA opportunity is recorded in `compiler.optimization.029`.

## Batch 2: dependency walks

An iterative dependency walk needs one visited bit per function: an active ancestor and a finished
child both skip a second visit. Its first visit alone schedules the post-order entry. A flat
pointer set replaces the node-based state map, without changing dependency order. Root-union
membership reuses a worker-local table cleared before each walk; this walk reads snapshots and
cannot execute another semantic job, so its table cannot be re-entered by a nested compile-time call.

Comparison: batch-1 integration `b0c6628cd` / build 699 versus the new code / build 700. Command:
`swc.exe build -w bin/std -m video -bc release --num-cores 6 --rebuild --log-ascii`, with the same
alternating three-pair, six-performance-core protocol. Baseline/candidate SHA-256:

- `85f0bcc7f178ca7b8586dbd8442dab99aa394f5b8b6c03f4fb0d8757c3a2bef1`.
- `5b3b1f62ffde66c786333476ee82b941d7124ea968eeb8bb387dc0b6301c2f18`.

Median paired elapsed time fell 10.33%; process CPU and cycles rose 7.31% and 7.37%. Two of the
three elapsed pairs improved. Absolute elapsed medians were 13.959 / 12.304 seconds. The CPU
tradeoff and shared-machine variation prevent interpreting this as a uniform work reduction or
extrapolating it to every module. All samples remain in the CSV.

Validation: 823 C++ tests passed, including the new dependency-order test covering a diamond,
cycle, ignored subtree and cache invalidation after a new edge. DevMode JIT
`--file-filter static_if_reflect_cycle.swg` passed two cases; Release built the real `aoc2024`
example and its core dependency closure. Both compiler configurations built successfully.
An initial `--file-filter recursive` selection was invalid because it excluded `testAlloc` and
`testFree` helpers required by one selected file; it is not counted as passing evidence.

Batch-2 integration with master `81e57b332` used Release build 702. Native
`--file-filter closure -bc release` passed 83 cases in JIT and in the emitted executable;
the backlog validator passed. This integration also brings the independent pattern-binding fix
`69f480e61`, which resolves the earlier `compiler.core.049` baseline failure.

## Discarded: MicroStorage accessor inlining

Release does not use LTO. Two experiments exposed unchanged instruction-storage method bodies
in the header: build 703 moved 29 iterator/view/accessor methods; build 704 kept only the 22
iterator/view methods. The comparison baseline was batch-2 integration `277804c1c`, build 702.
Neither variant was retained.

| Experiment | Pairs / workspace | Median paired elapsed | CPU | Cycles | Peak working set |
| --- | --- | ---: | ---: | ---: | ---: |
| All 29 methods | 3 / all standard modules | +10.98% | -6.53% | -6.01% | +0.01% |
| All 29, common resource root | 7 / core | +4.34% | +1.03% | -2.92% | -0.98% |
| Iterators/views, common resource root | 5 / core | -2.79% | -3.27% | -3.54% | +1.56% |
| Iterators/views, common resource root | 3 / gui | +17.18% | +19.14% | +18.93% | -1.97% |

The narrower variant's modest core improvement did not hold on gui: two of three elapsed pairs
regressed. All builds succeeded. Shared-machine activity remains a material source of variation;
no favorable samples have been selected out of these series. Both candidate executables were
slightly smaller than the baseline, but binary size does not justify the elapsed-time result.

For the common-root controls, both compiler copies live in the same external directory and use
the same runtime/std resource junctions into this worktree. This removes a possible resource-path
confound in earlier comparisons. The six pinned performance workers and alternating A/B, B/A
protocol remain unchanged. Exact binary SHA-256 values:

- Baseline 702: `3a7cd18ae95e5dec12e190ad7847084a0ad27dfcab6a1a3e4c00d444eac4758b`.
- Full variant 703: `bf8428c7411fc20ebf85c35282680c77999913615b35aff0ec2db7cfdad1143e`.
- Iterator variant 704: `5046b1c59096a48e6c8de59d3d8db0106752183d4adb5d3a0af5e013a8dd4fc5`.

Functional checks on the full 703 variant: Release compiler/program `release`, video
`--test-file y4m.test.swg`, 13 passed in JIT and native; DevMode compiler/program `release`,
native `--file-filter simd`, 49 passed in JIT and native. The narrower 704 variant completed its
paired contextual builds; no additional functional campaign was run after rejecting its timing.

## Discarded: JIT order lock transfer and vector reuse

Build 710 returned the cache's existing shared lock to its visitor instead of taking a second
read lock on a cache hit. It also reused local vectors in the dependency walk and completion
loops. The baseline was the same build 702, using the common-root control protocol.

The first two gui pairs completed, but the third candidate failed during gui code generation:
`internal compiler error: job 'CodeGen' returned an error without a diagnostic` (exit 5).
That failed sample is retained in the CSV and excluded from timing comparisons. The first
candidate also overlapped substantially more background CPU (41.69%, versus baseline 17.17%);
the successful pairs establish no elapsed-time gain.

Functional checks before that failure passed: Release/program `release`, reference
`--file-filter 014_002_run.swg`, five tests; DevMode `unittest --dev-full`, 861 C++ tests including
cache hit, early predicate exit and subsequent invalidation; DevMode JIT
`--file-filter const_eval_pointer`, five tests. Both compilers built successfully.

The exact gui rebuild then passed once in DevMode. Three additional pinned, six-worker rebuilds
with the unchanged Release baseline all passed. This does not establish the failure's cause or
prove that the baseline cannot fail; the prototype was discarded and was never merged. Its
external patch and both executable copies are retained for isolation of the locking and buffer
changes. Candidate SHA-256: `9f719153f0c4e5cc5e7c640cb57686de2a20ba8df3c8f5572d58d33c558febac`.

## Batch 3: JIT root verdicts and global-function membership

An accepted optional constant root immediately enters `seenFunctions`, so a second cache only
needs to remember rejected optional roots. A worker-local `PointerSet`, cleared on every walk,
replaces the boolean unordered map. Strict relocations still bypass the optional rejection cache.
Global-init relocation collection also uses a flat pointer set to avoid allocating one node per
visited function; its traversal order and offset filtering are unchanged.

Baseline: master `75dedcebe`, Release build 712. Candidate: the same compiler plus this batch,
build 713. Both live under the same external resource root. Command:
`swc.exe build -w bin/std -bc release --num-cores 6 --rebuild --log-ascii`.
All twelve standard modules are rebuilt; three pairs alternate A/B, B/A, A/B on six P cores.

| Median paired change | Result |
| --- | ---: |
| Elapsed time | -3.69% |
| Process CPU time | -3.44% |
| Process cycles | -3.89% |
| Peak working set | +0.00% |

All three elapsed pairs improved. Absolute elapsed medians were 25.763 / 24.813 seconds.
The gain is modest and remains subject to shared-machine variation; the report retains every
sample and its background CPU reading. Baseline/candidate SHA-256:

- `28276d2ef4fac2f6d29a3008c9ede9b04907a66b16e621440a7e173bbcbfc8dc`.
- `96d8637c76af371481ee36d708ed398f33950eceb6576fdc2d4668d3d10ba6f1`.

Both compiler configurations built successfully. Validation rotated to these boundaries:

- Release compiler/program `release`, native `--file-filter global_function_ptr.swg`:
  one passed in JIT and native.
- Release compiler/program `release`, Swag Capture `--test-file serialization.test.swg`:
  three passed, after compiling the complete application and its eight dependency modules.
- DevMode compiler/program `devmode`, JIT `--file-filter dynamic_recursive_constraints.swg`:
  one passed.
- All six measured standard-workspace builds completed successfully.

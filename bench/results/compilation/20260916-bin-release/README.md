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
3,248 successes; the unchanged build-688 baseline reproduces it in isolation. It is tracked by
`compiler.core.049`. The remaining SSA opportunity is recorded in `compiler.optimization.029`.

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

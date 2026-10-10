# Optimization Backlog

Intermodule and backend optimization, register allocation, final image layout, and the performance
of the code `swc` generates.
Frontend and lowering defects are [compiler.core.md](compiler.core.md).

Entries are ordered from the most recently updated down. [README.md](README.md) defines
the shared backlog conventions. Instruction counts, runtime winners, and timing results describe
the cited revision or the entry's last measurement; they must be remeasured before guiding a new
optimization. A campaign called the latest below was the latest at that measurement, not a moving
claim about the current checkout.

Several entries address register residency, loop-entry shape, spill traffic, aliasing and
inline argument materialization. Earlier measurements used the whole-hull allocator; optimizing
builds now use interval splitting, so those measurements identify workloads to recheck rather than
current performance guarantees. `MicroSsaState` reconstructs SSA and phi values for analysis, while
the executable Micro instruction stream has no explicit phi instruction. Since build 438, a call
that the straight-line path steps over — a safety panic, a cold refill — no longer constrains the split
allocator: a value crossing it in a caller-saved register is parked in its home inside the cold
block, and the hot path keeps the register.

The intermodule program below applies to **every Swag module whose matching implementation is
available locally**: application modules, sibling workspaces, vendored dependencies, package
caches, third-party checkouts, and the standard library. Availability and semantic proof decide
eligibility; origin, license, module name, and installation path do not. An open-source dependency
benefits because its implementation can be analyzed. A proprietary dependency supplied with source
gets the same benefit. No transformation in this program may require a `std` whitelist or a
library-specific name match.

Source availability and a closed set of callers are separate facts. A body can be available for
optimizing a known direct call while exports, plugins, callbacks, or a replaceable shared library
still prevent whole-program assumptions. Preserve a canonical externally callable version wherever
the boundary requires it. A local file with the same module name is not proof that it implements
the binary selected by the build. Other-language sources require a supported frontend or compatible
optimization representation; merely finding their text does not make them Swag bodies.

The intended pipeline is resolved typed bodies and summaries, global symbol/call resolution,
bounded interprocedural transformations, ABI lowering, the existing Micro pipeline, then final
layout and relocation. Reuse semantic analysis and local passes. Keep compile-time execution as
a separate consumer of the resolved program; importing a body must not re-execute module setup
or compile-time side effects.

These waves express dependencies, not promises of measured speedups. Each entry owns an
independently finishable outcome and stays here while its next outcome remains open.

| Wave | Deliverable | Entry identifiers |
| --- | --- | --- |
| Foundation | Local implementation discovery, typed bodies, global index, incremental reuse | compiler.optimization.106, compiler.optimization.107, compiler.optimization.108, compiler.optimization.109 |
| First useful release | Effect summaries and automatic intermodule inlining | compiler.optimization.110, compiler.optimization.111 |
| Contextual optimization | Specialization, devirtualization, aggregate transport, allocation elimination, loop proofs, partial inlining | compiler.optimization.112, compiler.optimization.113, compiler.optimization.114, compiler.optimization.115, compiler.optimization.116, compiler.optimization.117 |
| Late code and data | Callee register contracts and whole-image liveness | compiler.optimization.118, compiler.optimization.119 |
| Measured deployment | Profile feedback and final code/data placement | compiler.optimization.120, compiler.optimization.121 |
| Advanced experiments | Partial evaluation, CPU variants, private data representations | compiler.optimization.122, compiler.optimization.123, compiler.optimization.124 |

For each implementation, select validation using
[validate-swag-changes](../.agents/skills/validate-swag-changes/SKILL.md). Import, publication,
identity, and cache cases belong in `bin/unittests/workspace`; runtime code shapes in `native`;
compile-time behavior in `jit`; guarded paths in `safety` or `sanity`; graph, cache, IR, ABI,
linker, and profile helpers in the corresponding C++ tests. Dedicated debug-information fixtures
opt into `--debug`. Scheduling/publication changes also exercise both compiler executables and
real parallelism. Follow shared load admission and six-worker limits for every command.

Before the first transformation, establish baselines for small and large module graphs, deep wrapper
chains, diamond dependencies, recursion, generics, callbacks, aggregate returns, and mixed source,
binary, and shared dependencies. Include a standalone third-party workspace outside `bin/std`.
Compile equivalent eligible modules under different names and roots, including a read-only package
root, and require equivalent decisions after path normalization. Synthetic cases prove decisions;
representative applications measure value.

Record runtime distributions, text/data size, startup and allocation counts where affected, cold
and warm build wall/CPU time, peak committed memory, imported-body counts, and incremental
invalidation fan-out. Compare enabled/disabled transformations with identical inputs/compiler
builds, unchanged-binary controls, and alternating runs on a quiet machine. Set explicit code-growth,
compile-time, and memory budgets from those baselines before default rollout; instruction-count
reductions alone do not establish a performance win. Measure a private helper edit, public signature
edit, unrelated edit, and profile change separately.

Expose deterministic decision records: unavailable/incompatible body, open binding, unsupported
semantics, insufficient benefit, exhausted budget, imported body, selected clone, and invalidating
dependencies. Preserve source/inline provenance, stack walking, diagnostics, cleanup, error
propagation, evaluation order, and effective safety/sanity/FP contracts. Optimization level must
not change which source programs are well-typed. Cheap proven transformations should become normal
for eligible modules; costly experiments stay selectable until measured. Keep existing `Never`,
`Inline`, and `NoInline` contracts explicit. This plan invents no command-line spellings or
new language syntax.


### compiler.optimization.045 — Branch simplification is a quarter of the backend, and every new pattern taxes every function

- Recorded: 2026-09-23 09:25
- Updated: 2026-10-10 14:54 — Skip operand decoding for irrelevant boolean-fold instructions.
- Taken on 2026-10-10: `coalesceShortCircuitResults` now maps virtual-register ids through `FlatKeyMap` to a contiguous vector of site records. This removes the node-based map's per-register allocation and pointer lookup while keeping the one-time site scan lazy. The Release compiler build succeeded, and the Release native `short_circuit_booleans.swg` test passed; no timing claim is made.
- Taken on 2026-10-10: after every use and definition of E has been renamed to D, its retained flat-table record is reset so the old `SmallVector` storage is released, matching the former map erase's lifetime. The Release compiler rebuilt, and the focused Release native test passed; no timing claim is made.
- Taken on 2026-10-10: `fuseMaterializedBoolBranches` now resolves the local setcc/copy chain before querying CFG flag liveness. Candidates rejected by that local match no longer trigger the CFG query; accepted candidates perform the same query before rewriting. The Release build succeeded, and the focused `branch_simplification.swg` and `short_circuit_booleans.swg` native tests passed; no timing claim is made.
- Taken on 2026-10-10: `foldDecidedBooleans` now fetches operands only for `SetCondReg` instructions or opcodes whose metadata says they may define CPU flags. Other instructions cannot affect the tracked flag definition or boolean result. The Release build and focused `branch_simplification.swg` and `short_circuit_booleans.swg` native tests passed; no timing claim is made.
- Taken on 2026-10-10: `convertEqualityChainsToBitTests` now records the matched body's last layout ordinal instead of pushing each instruction index into a temporary vector. Accepted links, including optional alias copies, are contiguous, so cleanup iterates the proven range and avoids the per-link index writes and dynamic body storage for longer chains. The Release build and focused `equality_chain_bit_test.swg` native test passed; no timing claim is made.
- Area: compiler/backend, compilation time
- Evidence: instrumented Release 0.1.1035 on `swc build -w bin/std -bc release --rebuild
  --num-cores 6`. The micro pipeline spends 65.3 s of worker CPU over 33,062 functions;
  branch simplification alone is 16.2 s of it, **24.8%**, across 72,546 runs of which 38.6%
  rewrite something. The next pass is register allocation at 11.3%, then instruction combine
  at 7.9%. A six-worker stack profile of the same build puts the pass at 12.9% of busy CPU,
  spread over some twenty sub-transforms none of which reaches 1.5% — there is no hot spot,
  only a battery of scans.
- How it got there: the cold release rebuild of the big modules slowed by half in one week at
  unchanged sources. Paired, order-alternated rebuilds give gui 12.3 s → 18.4 s and pixel
  6.5 s → 11.1 s between 0.1.684 (2026-09-16) and 0.1.1035 (2026-09-21), while gui's sources
  moved from 105,315 to 105,483 lines. Bisecting the same measurement puts 0.1.823
  (2026-09-17 01:33) still at the old speed and 0.1.885 (2026-09-17 13:29) already at the new
  one — the window that added some fifty narrowing, diamond and short-circuit patterns.
- Taken in 0.1.1046: seven transforms opened on the same walk of the function and ten more
  rebuilt the same jump-target counts and relocation set; one shared walk now serves a run and
  is dropped when a transform rewrites the stream. Single-core, alternated: core 0.97, pixel
  0.93, gui 0.95, video 0.92, seven of eight pairs favourable. `buildProgramLayout` fell from
  1.67% to 0.73% of busy CPU.
- What remains: the pass still runs about thirty-seven transforms, and each one scans the whole
  function looking for a shape most functions do not hold. The cost is therefore the number of
  patterns times the size of every function compiled, which is why a pattern campaign shows up
  as a compile-time regression with no single culprit.
- Measured, and the obvious gate is not worth it: instrumenting the pass over the same rebuild,
  38 592 runs land on a function holding no conditional jump at all and cost 2.42 s of the pass's
  33.1 s — **7.3%**, about 0.9% of the compilation. Gating them would also have to spare the
  structural loop, which threads unconditional jump chains and erases unreachable code in exactly
  those functions, so the reachable share is smaller still. Do not spend a gate on it.
- What the same probe does say: a run on a 28-instruction branchless function still costs 63 us,
  against 485 us for a 126-instruction branchy one. The pass has a large **fixed** cost per run —
  entering some thirty-seven transforms, each with its own scratch containers — that does not
  scale with the function. That, not the scanning, is what a pattern campaign multiplies.
- Where the fixed cost was (timed per transform, 0.1.1047): fourteen transforms opened by asking
  for the next free virtual integer register index, which walks every instruction and collects
  every register operand, and then used it only when the transform actually rewrote something;
  the short-circuit coalescer opened with a use/def query per instruction and a pair of ordinal
  lists per register, read only after three filters had matched. Collecting both on first request
  took the pass from 16.7 s to 9.1 s of summed worker time over a bin/std release rebuild.
- The same shape again, taken in 0.1.1048: `areCpuFlagsDeadAfterInCfg` mapped an instruction
  reference back to its graph index with a linear search of the graph's instruction list, and
  eleven sites ask it once per candidate they examine - quadratic in the function.
  `MicroControlFlowGraph::indexOf` now answers from a table built on first request.
- Ranking at 0.1.1048, as a share of the pass: `fuseMaterializedBoolBranches` 10.6%, rebuilding
  SSA through `MicroSsaState::ensureFor` 10.3%, `convertEqualityChainsToBitTests` 9.9%,
  `convertGuardedSelectDiamonds` 8.9% (which rebuilds SSA of its own), `coalesceShortCircuitResults`
  7.2%, and a tail of thirty-odd transforms under 4% each. The measured quadratic and virtual-register
  prologues were removed; what remains is the cost of asking thirty-seven questions about every function.
- Taken in 0.1.1136: equality-chain bit tests, packed switches, three-way signs and repeated memory
  compares had each built a hash set from the same relocation list. They now share one index while
  the instruction stream is unchanged and rebuild it after a rewrite. A run without rewrites makes
  one relocation walk instead of four; the transforms consult the same instruction references as
  before. Four focused native Release tests and one rotating JIT test passed. Five order-alternated
  pairs against the same master source gave candidate/baseline wall and CPU ratios of 0.836/0.763
  for core rebuild, 0.968/0.969 for core touch and 0.860/0.955 for hello build; the no-op guardrail
  stayed below 100 ms. Rebuild times drifted from 1.8 to 3.4 s during the run, so this is a
  correctness-certified structural saving, below the measurement floor rather than a claimed
  percentage speedup. Peak working-set ratios were 0.992, 1.000 and 0.983 for those three builds.
- Taken in 0.1.1138: `coalesceShortCircuitResults` and `threadShortCircuitExits` each rebuilt the
  program layout in every short-circuit round. They now use the same layout when coalescing makes
  no change, and rebuild it when coalescing rewrites the stream. This removes one full instruction
  walk from each unchanged round, with no change to either transformation. The prior profile put
  all `buildProgramLayout` calls at 0.73% of busy CPU, so this is expected below the whole-build
  timing floor. The focused `short_circuit_booleans` and `short_circuit_past_join` native Release
  tests passed; the rotating `std/core` TweakFile file ran four passing tests. On the rebased master,
  five order-alternated pairs gave candidate/baseline core-touch ratios of 1.013 wall and 0.989
  CPU. Hello-build ratios of 1.126 wall and 1.150 CPU reversed in a second seven-pair run with
  A/B roles swapped: 0.995 wall and 0.857 CPU. The series therefore supports no percentage claim.
  Peak working-set ratios were 1.014 for core touch and 1.034 for hello build in the five-pair run.
- Ruled out on 2026-09-24: recording whether each function has `SetCondReg` in the shared branch
  scan and using it to skip the equality-chain, branchless-or and three-way-sign transforms when
  none exists. This requires one extra opcode comparison per instruction in every branch scan.
  The three focused native Release tests and a rotating JIT test passed, but five alternated pairs
  measured candidate/baseline at 1.090 wall and 1.030 CPU for core rebuild, and 1.144 wall and
  1.190 CPU for hello build. Peak working-set ratios were 1.010 and 0.993. An earlier sweep was
  discarded when unrelated machine load stretched one rebuild to 29.5 s. The completed sweep still
  shows the always-paid scan cost outweighing the scans avoided here; the gate was reverted.
- Taken in 0.1.1140: the early unused-label sweep reused the pass's relocation-reference index
  instead of walking the same relocation list and allocating another hash set. A run without
  rewrites now builds this index once for the early sweep and the later equality-chain, packed-switch,
  three-way-sign and repeated-memory-compare transforms. The index is invalidated after a rewrite.
  The focused native Release branch-simplification and packed-switch files passed, as did four
  tests in the rotating JIT `defer.catch` file. Three order-alternated pairs against the same
  master source gave candidate/baseline core-rebuild ratios of 0.985 wall, 0.944 CPU and 1.005
  peak working set. Hello-build ratios of 1.198 wall and 1.244 CPU reversed in a seven-pair run
  with A/B roles swapped: baseline/candidate 0.999 wall and 1.036 CPU. Other attempted pairs
  were discarded when shared-machine load stretched individual builds to 26-35 seconds. The
  saving is therefore below the measurement floor, with no percentage speedup claim or stable
  memory regression.
- Ruled out on 2026-09-24: returning an unusable diamond scan when its existing label-reference
  map is empty. This skips the diamond transform family for functions with no direct jumps,
  without adding an opcode check to the instruction walk. Two focused native Release tests and
  the rotating JIT `move_value_expression` file (15 tests) passed. Five alternated pairs gave
  candidate/baseline ratios of 1.058 wall and 1.044 CPU for core rebuild, and 1.041 wall and
  1.038 CPU for hello build; peak working-set ratios were 0.998 and 1.014. A reverse series
  became unusable when unrelated load stretched a baseline rebuild to 42.8 seconds. With no
  observed gain and a possible guardrail regression, the gate was reverted.
- Final validation on 2026-09-24: the Release campaign passed 1,500 JIT tests and 3,478 native
  tests, then stopped on a semantic error in `std/gui`, since fixed by preserving the source view of generated `is`
  casts. The pre-campaign compiler build 1131 reproduced that error on unchanged GUI sources.
  A final five-run four-workload timing attempt was stopped after three runs:
  unrelated machine load moved a core rebuild from 4.8 to 7.3 seconds and a touched-file
  build from 3.0 to 9.2 seconds. These samples support no final percentage speedup claim.
- A final three-pair, order-alternated comparison of build 1131 with build 1140 on the same
  checkout measured final/initial ratios of 1.035 wall, 1.051 CPU and 1.010 peak working set
  for core rebuild; hello build measured 1.005 wall, 1.000 CPU and 1.011 peak working set.
  Several other compiler changes landed between those versions, and the shared machine drifted
  during the campaign. This end-to-end comparison neither proves a speedup nor attributes the
  small slowdown to one batch. The remaining distance to the subsecond core target is large.
- A separate final three-run check of build 1140 gave a warm no-op median of 78.1 ms
  (all three runs below the 100 ms guardrail) and a touched-file median of 3,241.7 ms.
  In the paired comparison above, the final compiler's core-rebuild median was 4,890.1 ms
  and hello-build median was 244.0 ms. These are noisy three-run observations, not the
  five-run quiet-machine baseline required for a stable target claim.
- Ruled out on 2026-09-25: tracking changes since the last graph invalidation instead of using
  the pass-wide `changed` flag at each synchronization point. A Release 1142 core profile put
  `MicroBranchSimplifyPass::run` at 10.27% and `MicroControlFlowGraph::build` at 3.35% of
  sampled worker CPU, so the predicted whole-build saving was below 1%. The Release 1143 trial
  passed two focused native files and a randomly drawn JIT file (12 tests), but five loaded
  A/B pairs gave `core_rebuild` candidate/baseline ratios of 1.249 wall and 1.234 CPU, while
  `core_touch` gave 0.808 wall and 0.872 CPU. A follow-up candidate core rebuild took 39.7 and
  39.9 seconds, yet the restored baseline also took 49.5 seconds during the complete Release
  suite. Five A/A pairs of byte-identical binaries gave 1.000 wall and 1.044 CPU, with individual
  builds between 2.7 and 5.8 seconds. The evidence does not isolate the candidate from shared
  machine load or establish a repeatable benefit. The change and version bump were reverted;
  the [campaign summary](../bench/results/compilation/20260925-speed/README.md) records the outcome.
- Taken on 2026-09-26 under prompt 4: the existing program-layout scan now also records whether
  any label exists. The branch pass skips jump-threading, immediate-label, inverted-jump, CFG
  reachability and unused-label sweeps when their required label is absent; it skips the diamond
  family when the current layout has no conditional jump. Each guard uses already collected layout
  state and falls back to the original path after a rewrite. Focused native Release tests passed,
  as did the full 3,480 native and 1,500 JIT test suites. Five order-alternated four-workload pairs
  against the earlier campaign binary were too variable for a speedup claim: candidate medians were
  2,366 ms core rebuild, 53 ms no-op, 2,571 ms core touch and 144 ms hello; baseline medians were
  2,299, 41, 2,224 and 129 ms. The full Release campaign reached the known `std/gui` semantic
  error, since fixed by preserving generated `is` cast source views; the
  pre-campaign master compiler also reproduced it.
- A second prompt-4 group on the merged master uses that same layout to skip range-check,
  range-and, branch-to-cmov and repeated-memory-compare scans when their required conditional
  jump or setcc is absent. The 3,480 native and 1,500 JIT Release tests passed. A five-pair A/B
  sweep was disrupted by shared load: core rebuilds grew from about 2 to 5-7 seconds during it.
  Candidate/baseline medians were 2,067/2,082 ms for core rebuild, 44/49 ms for no-op,
  1,830/1,929 ms for core touch and 126/120 ms for hello. This supports no percentage claim.
- A third prompt-4 group skips rich branch-reference scans for float selects, equality chains and
  packed switches when their required opcodes are absent. It also skips implied-branch label maps
  without an immediate compare and stores each label's reference count and jump position in one
  map instead of two. Focused tests, 3,480 native and 1,500 JIT Release tests passed. Five paired
  core rebuild medians were 3,151 ms candidate and 2,996 ms baseline under variable load; hello
  medians were 167 and 189 ms, but a seven-pair role-reversed hello series gave 181 and 187 ms
  with slightly higher candidate CPU. No speedup percentage is established. The full Release
  campaign again reached the `std/gui` error later fixed by preserving generated `is` cast
  source views.
- A fourth prompt-4 group skips settled register-allocation sweeps after checking for remaining
  virtual operands, defers implied-branch and jump-chain cycle sets, builds packed-switch jump
  counts only for qualifying chains, delays range-check used-set work until the opcode shape
  matches, and constructs short-circuit scratch maps only on paths that use them. Focused Release
  tests passed; after merging master `f196225e0`, 3,481 native and 1,500 JIT tests passed. The
  full Release campaign compiled `std/gui` and stopped in `std/video` because
  `Slice.predictIntraPlane` still changed after 24 pre-RA sweeps. The unmodified master compiler
  at `f196225e0` reproduced that exact failure with a video rebuild. Five order-alternated
  four-workload pairs against that master gave candidate/baseline medians of 3,357/3,426 ms
  core rebuild, 89/65 ms no-op, 2,734/2,576 ms core touch, and 245/242 ms hello. One touch
  took 35 seconds and one no-op 1.55 seconds under shared load; these samples establish no
  speedup percentage or stable regression.
- A fifth prompt-4 group defers the short-circuit fallthrough-label map and boolean-guard
  claimed-reference set, skips two diamond reference scans without a conditional jump, and uses
  existing layout flags to skip range and boolean-threading scans without their required
  immediate compare or setcc. Focused tests, 3,481 native and 1,500 JIT Release tests passed,
  including after merging master `0308e681d`. Five order-alternated pairs against the preceding
  integrated master `43766f77f` gave candidate/baseline medians of 2,269/2,304 ms core rebuild,
  46/57 ms no-op, 2,460/1,904 ms core touch and 152/145 ms hello. Paired rebuild and touch
  ratios were near one, individual touch runs ranged from 1.8 to 4.0 seconds, and the samples
  establish no percentage speedup. A fresh `std/video` rebuild still stops at the 24-sweep
  `Slice.predictIntraPlane` error; compiler `01e0d9e59`, before both recent master changes and
  these two prompt-4 groups, reproduces the same error.
- The 2026-09-28 prompt-4 continuation reuses the current branch scan's register-mention counts
  in short-circuit and range-AND folding, avoiding their separate whole-function counts when no
  preceding rewrite invalidated the scan. OR-chain and packed-switch candidate maps also reuse
  buckets within a run. Focused Release checks and the full 3,483 native and 1,500 JIT suites
  passed; elapsed time, CPU, and retained-memory effects remain unmeasured.
- The October 7 prompt-4 pass removes late branch scans' unused register-mention counts and
  shares layout with short-circuit return threading. Related backend work initializes combiner
  temporary indices once, defers boolean-merge facts and memory/flag proofs until a candidate
  needs them, sorts the initial interval queue once, and skips edge and rematerialization
  analysis for unsplit values. Definition indexing starts only when a rematerialization candidate
  needs it; address shapes precede SSA-use counting, and comparison patterns stop their neighbor
  walks at the first mismatched opcode. Release `swc.exe` passed the 293 native optimizer tests
  in the Release program configuration throughout. The final revision passed 3,651 native tests
  in the guarded program configuration; a preceding milestone, already incorporating the
  unused-binding syntax change, passed 1,515 JIT tests. Static instruction
  comparisons retained the tested function bodies; optional constant-call folding and the
  imported test-source edits changed some test wrappers. No elapsed-time, CPU or peak-memory
  measurements were taken. Reprofile before attributing a new pass share or claiming the threshold
  below.
- Next: two of the five now pay for an SSA rebuild, which is compiler.optimization.029's subject
  rather than this entry's. For this entry, the remaining lever is structural — running the
  pattern battery once on the converged IR instead of in every sweep of the pre-RA loop, the way
  `lateBranchSimplifyPass_` already does for three transforms. That changes what the optimizer
  produces, so it needs the benchmark, not just a compile-time measurement.
- Complete when: adding a pattern no longer adds a full function scan to every run, or the pass
  drops below 15% of micro-pipeline CPU on the `bin/std` release rebuild.
- Related: compiler.optimization.029, compiler.optimization.039.


### compiler.optimization.024 — The split allocator claims a whole instruction for an implicit operand

- Recorded: 2026-08-29 15:41
- Updated: 2026-10-10 14:51 — Index register pools directly during interval walks.
- Area: compiler/backend
- State: the interval-splitting linear scan of Wimmer & Mössenböck (VEE 2005, the allocator
  of HotSpot's client compiler) is what every optimizing build allocates with. `-O0` keeps
  the earlier scan, which also remains the fallback whenever a precondition fails or the
  walk bails, and the C++ conformity cases run both.
- The 2026-09-28 prompt-4 continuation replaced fill-copy construction of fresh value and
  fixed-claim interval arrays with direct default construction. The call sites pass empty
  vectors, so each interval starts with the same fields while no empty `LiveInterval` is
  copied for every register. The Release `interval` selection passed two native tests; timing
  and peak memory were not measured.
- Taken on 2026-10-10: guarded-call parking after interval assignment now skips its entire call
  loop when `guardedCallPositions_` is empty, and otherwise visits only entries in the existing
  ordered `callPositions_` list rather than every instruction index. The guarded-position vector
  is populated only after a valid region containing a call is found, and call positions retain
  ascending instruction order, so node processing is unchanged. The Release build and focused
  native `private_spill_cold_call.swg` test passed; no timing claim is made.
- Taken on 2026-10-10: `coalesceSameValueCopies` now checks its already-built dense use/definition
  lists before fetching an instruction and decoding operands. Anything other than one virtual use
  and one virtual definition cannot satisfy the full-register-copy matcher or its later assertion.
  The Release build and focused native `physical_copy_intervals.swg` test passed; no timing claim
  is made.
- Taken on 2026-10-10: copy-join analysis now tracks the number of candidates still eligible for
  renaming and ends its instruction scan as soon as each candidate has been rejected. It avoids
  decoding remaining instructions after the result is fixed; no join decision changes. The Release
  build and focused native `physical_copy_intervals.swg` test passed; no timing claim is made.
- Taken on 2026-10-10: `buildLiveIntervals` now checks the existing dense use/definition lists
  before fetching an instruction to find copy hints. A hint needs exactly one virtual destination
  and at most one virtual source, including copies from physical registers. The Release build and
  focused native `physical_copy_intervals.swg` test passed; no timing claim is made.
- Taken on 2026-10-10: the zero-high analysis in `coalesceSameValueCopies` skips instruction
  lookup when all of an instruction's destinations already have a definition that disproves the
  property. The state only changes from true to false. The Release build and focused native
  `physical_copy_intervals.swg` test passed; no timing claim is made.
- Taken on 2026-10-10: `analyzeLiveness` now skips operand-width lookup for instructions with no
  virtual uses or definitions; only virtual registers consume the resulting `wideFloat` marks.
  It also uses the opcode's metadata to skip fetching operands when the opcode cannot carry a
  variable 128-bit operand, or is fixed 128-bit. The Release build and focused native
  `physical_copy_intervals.swg` test passed; no timing claim is made.
- Taken on 2026-10-10: the final copy-join scan now collects explicit and encoder-implied register
  references lazily, only if an instruction touches a candidate register. Untouched instructions
  no longer perform this lookup. The Release build and focused native
  `physical_copy_intervals.swg` test passed; no timing claim is made.
- Taken on 2026-10-10: `computeGlobalBenefits` returns its already-zeroed result without scanning
  instructions when `hasControlFlow_` is false; `isFlushBoundary` rejects every instruction in
  that state. The Release build and focused native `physical_copy_intervals.swg` test passed; no
  timing claim is made.
- Taken on 2026-10-10: the final copy-join scan now delays instruction lookup and full-copy
  decoding until a candidate register is touched, and only checks copy shapes with one dense use
  and definition. Untouched instructions avoid both operations. The Release build and focused
  native `physical_copy_intervals.swg` test passed; no timing claim is made.
- Taken on 2026-10-10: interval register election now chooses the best free register while it
  computes fixed-register intersections, retaining the winning intersection for the call-boundary
  check. This removes a second pool traversal and one repeated interval-intersection search for a
  free register ending at a call. The Release build and focused native
  `private_spill_cold_call.swg` test passed; no timing claim is made.
- Taken on 2026-10-10: edge resolution now locates a split or parked value node by binary search
  in its already sorted, disjoint per-value node group, with a direct check for unsplit values.
  The Release build and focused native `physical_copy_intervals.swg` and
  `private_spill_cold_call.swg` tests passed; no timing claim is made.
- Taken on 2026-10-10: fixed-interval construction now checks concrete-source liveness directly
  for the usual zero- or one-successor copy case, keeping the general scan for multiple successors.
  The Release build, focused `physical_copy_intervals.swg`, and complete native Release suite
  (3,690 tests) passed; no timing claim is made.
- Taken on 2026-10-10: interval election now builds per-class physical-register-to-pool-index
  tables once, replacing repeated linear pool searches for active and inactive nodes. The Release
  build and focused native `physical_copy_intervals.swg` and `private_spill_cold_call.swg` tests
  passed; no timing claim is made.
- Evidence: the walk describes every concrete claim by the position it occupies, except
  for the forms that name a register implicitly - the `rax`/`rdx` pair of a multiply-high,
  the `cl` of a variable shift, a compare-exchange. Those keep a claim on the whole
  instruction, so no operand of theirs can share it, and the second legalization sweep can
  then need a short save/restore borrow from `tryBorrowReservedRegister`.
- Oct 6 resolved scope: definition-only RDX claims now start at the output of register/register
  and register/memory binary instructions. Dying multipliers can occupy RDX without consuming
  R8/R9; carried values, read/write RAX, division and shifts retain their input protection.
  The Release optimizer regressions pass, including signed/unsigned boundary quotients and
  inputs retained across multiply-high sequences. This is a structural register-pressure gain.
  The user explicitly accepts such proof without a measurable runtime improvement.
- Runtime evidence: the focused four-task Release A/B established no target gain and produced
  an adverse fannkuch signal. Keep the [patch and all samples](../bench/results/generated-code/20261006-mul-claims/README.md).
  Investigate that allocation/layout interaction separately; it is not an independently
  confirmed regression, and no runtime gain is claimed for the retained rule.
- Next: audit the remaining shift and compare-exchange constraints. Preserve the resolved
  multiply output rule and diagnose remaining borrow sites on a whole-library build. The
  global legalization reserve has been removed; compiler.optimization.035 tracks local spills.
- Complete when: the three forms carry position-precise fixed intervals, the borrow path no
  longer fires on a whole-library build, and the suites stay green.
- Related: compiler.optimization.016.


### compiler.optimization.126 — Auto-inline cannot volunteer a body with a postfix `!` or a nullable signature

- Recorded: 2026-10-10 11:07
- Updated: 2026-10-10 13:53 — Keep the inline proof-boundary repair and reject broad eligibility after sentinel frame traffic grows.
- Area: compiler/sema, automatic inlining and flow narrowing.
- Evidence: binarytrees calls `benchAlloc` and `benchFree` once each per node and each has a single call
  site, yet neither is inlined. `measureAutoInlineBody` in `Parser.Func.cpp` blocks every
  `ErrorManagementExpr`, and the postfix not-null assertion shares that node (`allocator!`); then
  `shouldAutoInline` refuses nullable parameters and returns when the body has calls. Exempting the
  `!` token and lifting the nullable rule inlines both: `bottomUp` plus `benchAlloc` 91 -> 73 static
  instructions, `release` plus `benchFree` 75 -> 63, two calls per node fewer; a scratch copy with
  explicit `#[Swag.Inline]` ran 13-19 % faster in a noisy window.
- Correctness repair retained: facts recorded while analyzing an inline body now stop at the frame
  that opens that expansion. The reference compiler rejects the caller's second `value!` in the
  standalone `inline_nullable_assert.swg` case, matching the earlier `m.alive!` failures in native
  aoc2024 day11 and day21; the focused sema suite checks the file with the repair.
- Rejected broad eligibility on the current revision: inlining both wrappers changed
  `Binarytrees.__main_0` from 26 to 70 optimized Micro instructions in `bottomUp` and from 19 to 60
  in `release`, with larger recursive frames. More decisively, `Wordfreq.__main_0` grew from 443 to
  508 optimized Micro instructions, and the `while i < n` loop gained extra frame loads and stores.
  This does not meet the sentinel no-loss rule; no timing was taken.
- Next: make eligibility depend on the actual call-site type and body flow, then prove a hot-path
  gain without volunteering one-time setup or adding frame traffic to sentinel loops.
- Complete when: single-call wrappers with `!` or nullable signatures auto-inline with no static
  per-iteration loss on any bench hot loop.
- Related: compiler.optimization.094, compiler.optimization.117.


### compiler.optimization.104 — The n-body pair loop keeps its pairs scalar

- Recorded: 2026-09-30 08:42
- Updated: 2026-10-10 11:07 — Contracted products separated by a load; recorded the rotation copies and a rejected position-loop unroll.
- Area: compiler/backend, loop unrolling, memory forwarding and SLP vectorization.
- Comparison: accepted campaign `20261001-103647`, built from `49f7e665d`, reports
  native at 23.5431 ms, JIT at 25.9971 ms and Zig 0.15.2 at 16.45 ms, with
  `CHECK=169096566666`. Native is 1.431x the current winner. The inspected Zig
  `ReleaseFast` timestep has 348 non-NOP machine instructions, 101 memory operands,
  four packed and two scalar square roots. This campaign predates the afternoon changes.
- Current shape: main's timestep has 395 non-label Microinstructions (399 with labels),
  131 actual memory accesses and 24 frame accesses. The position loop within it has
  15 non-label instructions, six memory accesses and no frame access.
  Contracting 31 additions and 19 subtractions of products removes 50 instructions from
  the previous 445, with no extra memory access or larger frame. Nine benchmark checksums
  stay exact; six other tasks keep their instruction/access counts, while raytrace and
  csvagg also lose instructions. Contraction requires `fpMathFma`, a supported encoder and proof
  that a distinct product is dead in every lane. Reusing a factor destination also preserves
  the original upper-lane source or proves those output lanes dead. Explicit `Swag.muladd`
  keeps its separate rounding.
- The timestep's ten roots remain scalar. Its 33 register copies use the full width,
  avoiding dependencies on old unused destination lanes. Earlier removal of integer/float
  transfers replaced cached integer bits with fourteen more memory accesses (117 to 131);
  that tradeoff still needs an accepted runtime comparison. The standalone `advance`
  uses 422 non-label instructions, 134 memory and 44 frame accesses in a 368-byte frame.
- Regression evidence: `20260930-152655` to `20260930-195406` changes native raw time
  from 24.8768 to 30.3729 ms (+22.1%); different control factors amplify that to +38.5%
  after normalization. JIT changes from 25.6579 to 24.8732 ms. At `f0a34dcf4`, native
  `#main` inlines `advance`, but JIT `#run` retains its call. JIT's 470 non-label Micro
  operations exactly match the native function at `819dd7872`, before borrowed-slice
  inlining. The old inlined timestep's partial register copies and packed encodings of
  scalar roots expose dependencies absent from the out-of-line shape. These are concrete
  code differences; their individual runtime contributions have not been established.
- Measurement limit: all four historical comparison cohorts on October 1 fail their
  declared control gates (p90/p10 <= 1.20, half-window drift <= 15%). The 13:16 cohort,
  after a 30-second warmup, has control spreads 1.292 for nbody and 1.549 for raytrace.
  All samples remain recorded. The accepted noon campaign observes a lower native time
  again, but its 17.35% calibration drift and different revision cannot establish a causal
  speedup for one fix. Repeat attribution on a stable machine without relaxing the gates.
- Rejected designs bound the next step: pairing roots after inlining extends coordinate
  lifetimes and raises hot frame accesses from 24 to 76; retaining them in GP registers
  still needs 73 and adds transfers. Late store-tree packing keeps scalar producers alive
  while rebuilding vector producers, reaching 119 frame accesses. A narrower scalar-capture
  trial removes one memory access but no instruction and leaves ten roots, with setup cost
  not yet justified. These prototypes were removed.
- October 3: the position loop now carries `base + i * 56` as a pointer (the induction-variable
  pass carries any scale no address mode forms), so it no longer multiplies and is no longer
  packed. Its packed form read vx/vy with one 16-byte load right after the timestep stored them
  as two 8-byte values; hand-written variants put that store-forwarding stall at about 3% of
  nbody (packed 24.61 ms min, scalar 23.85, packed with two 8-byte loads 23.88). The SLP pass
  already refuses an overlapping store in the same block, and a probe found no packed load
  after a narrower aliasing store in an earlier block or trip in the 12 tasks or in std core,
  pixel and video, so no separate rule was kept. Pairing only the ten roots and divisions was
  retried: 1.21-1.24x slower, frame accesses in `advance` 44 to 103.
- Zig and Rust inline the timestep and keep the 35 body fields in registers across steps.
  Swag calls `advance` once per step, saving and restoring ten XMM registers, and reloads the
  bodies through the slice. Zig issues 6 roots and 6 divisions per step, Rust 7 + 7, clang and
  Swag 10 + 10, in the order of their times (16.0, 19.7, 21.6 and 21.4 ms).
- Remaining gap: pack coordinate producers, roots/divisions and their scalar consumers as
  one plan, with a register-pressure estimate. Pairing only the expensive operations is
  insufficient. The position loop already packs x/y updates without frame traffic.
- October 10: post-RA contraction now reaches a product separated from its accumulation by the
  accumulator load (`2f0ebbbd8`): the step loop went from 393 to 378 instructions per iteration with
  131 memory operands and 24 frame accesses unchanged. The loop still carries 33 full-width register
  copies per step: velocity values move between XMM registers at the unrolled pair boundaries
  (`xmm7 = xmm9; xmm9 = xmm10; xmm4 = xmm11`), the interval walk splitting a long-lived value when a
  pair temporary takes its register. Pre-RA the loop holds 100 float copies; the allocator coalesces
  all but those. One accumulation per step stays unfused because its accumulator load reuses a factor
  register (`xmm3 = xmm8 * xmm12; xmm3 = xmm3 * xmm10; xmm10 = [m]; xmm10 += xmm3`).
- Rejected (October 10): canonicalizing the position loop (`%c = 5; H: cmp %c, 0; je X; ...; sub %c, 1;
  jump H`) into the counted shape so it fully unrolls. The pointer step stays an in-place `add` per copy,
  so no displacement folds; the forwarded velocities then live across the copies and spill, and main
  grew from 721 to 806 instructions. A countdown unroll needs the pointer carried as per-copy constant
  displacements and a pressure check on forwarded values first.
- Next: compare each interaction region against the winner and design shared producer
  ownership before another SLP rewrite. Keep historical timing attribution separate from
  the static optimization loop; a stable controlled cohort is still required for it.
- Complete when: the step retains or packs body state with no redundant pair work and
  matches the winner's packed roots/divisions without a generated-code loss in other tasks.
- Related: compiler.optimization.016, language.design.037.

### compiler.optimization.055 — Keep both quicksort global pointers resident across comparator calls

- Recorded: 2026-09-25 11:15
- Updated: 2026-10-06 20:59 — Private-global hoisting and value numbering landed after the last qsort dump; re-dump before further work.
- Area: compiler/backend, loop-invariant code motion and call effects
- Evidence: LDC keeps `g_Idx` and `g_Cnt` pointers outside wordfreq's inner quicksort comparisons; Swag previously reloaded them from RIP-relative globals each turn. An earlier LICM experiment using `SymbolFunction::isPure()` did not help because the bodyless `Swag.memcmp` declaration was not pure; increasing the purity budget and recognizing `Swag.vecmask` also left it impure. A `ReadOnly` call contract now explicitly promises no caller-visible writes and survives module API export. LICM uses that contract only for direct 64-bit global loads. The resulting `qsort` initially grew from 126 to 134 instructions because it spilled hoisted pointers. The allocator then proved to reserve a whole persistent register for legalization solely because `mayNeedLegalizeScratchRegister` reported `true` for a zero-operand `ret` (its only reported instruction in `qsort`). Correcting that answer lets the allocation use `r15` and removes two instructions: the first comparator loop drops from 10 instructions and 5 memory operands per unequal-count iteration to 9 and 4, and the second from 9 and 4 to 8 and 3. The full function has 132 instructions. An experiment admitting the preferred local-stack-base register to the interval pool alone changed no emitted instructions and was reverted. The wordfreq checksum remains 130489. Csvagg's 1,076-instruction `main`, 271-instruction row span, and checksum 24828641 remain unchanged. The 1,107 C++, 3,480 native, and 1,500 JIT tests pass. No timing sample informed the decision.
- Current evidence: the new loop-guided wrapper rule inlines both `less` calls in `qsort`. Its optimized body grows from 72 to 132 Micro instructions, while each unequal-count comparison now reads the retained `g_Idx` and `g_Cnt` pointers without a `less` call or a global reload. The tie path still calls `memcmp`, and the second comparator loop reloads both global pointers on entry. LDC also retains its pointers during the unequal-count loop and reloads after a call. Wordfreq's checksum is 130489; csvagg's selected function counts and checksum are unchanged. No timing sample informed the rule.
- A value-numbering trial preserved mutable global loads across a direct `ReadOnly` call. It removed four instructions from `qsort` as a whole (132 to 128), including a repeated global pointer load after `memcmp`, and kept checksum 130489. The extra live value changed allocation in the first comparator loop: each increment path acquired a stack reload of the count pointer and an unconditional back-edge jump. That hot-path regression outweighed the colder tie-path saving, so the trial was reverted without timing it. A direct-call regression test for this trial was reverted with the rule.
- Since that dump: LICM hoists a load of a private global (one no other module names and whose address no use binds) past pointer stores, but only out of an innermost loop (`ba4e255d4`, then `baedb50db` after a 22% wordfreq regression when the hoisted `g_Text` had to outlive nested loops), and value numbering reuses unmodified private globals across disjoint writes (`a172a3428`). `g_Idx` and `g_Cnt` are file-level `late var` globals in `bench/src/swag/wordfreq.swg`; no `qsort` dump has been taken since these changes.
- Next: dump the current Release `qsort`. If the post-call and second-loop reloads are gone, retire the entry; otherwise compare the tie path and post-call pointer recovery against LDC, then use paired runs when machine load permits to decide whether the remaining reloads warrant a focused allocation change.
- Complete when: both pointers remain resident through the comparator calls without extra spill traffic and checksums remain correct, or the current dump shows this gap has already closed and the entry is retired.

### compiler.optimization.011 — A SIMD routine keeps its strides and counts in the frame

- Recorded: 2026-08-24 13:31
- Updated: 2026-10-06 20:59 — Removed the pointer to the resolved Inflate cursor lead.
- Area: compiler/backend
- Found while: std.video.001, after mem2reg was taught the vector load and store and the memory traffic
  of the motion-compensation path fell by a quarter.
- Observation: promotion now reaches the vector temporaries, so the intermediate values of a
  `#simd` expression stay in registers. What is still in memory is everything the local
  allocator put there: `Video.H264.mcChroma` emits 635 instructions with 81 frame stores and 119
  frame loads, and its interpolation loop reloads the two splat sources on every row. The loop of
  `Video.H264.copyPlane` shows what the shape should be — after post-RA hoisting learned that a
  private frame cannot be reached by a store through a program pointer, its sixteen-byte copy is
  seven instructions with no frame access at all — and mcChroma does not get there because its
  own locals escape into helpers, which keeps its frame from being private.
- Evidence: 2026-08-24, release, `#[Swag.PrintMicro("post-emit")]`. mcChroma 707 -> 635
  instructions and 108 -> 81 frame stores across this pass; copyPlane 111 -> 104 instructions,
  its hot loop 10 -> 7 with 3 -> 0 frame accesses. The decode of one 2496x1440 picture went from
  10.1 to 8.5 ms of processor time (minimum of five interleaved pairs), and motion compensation
  is 44 percent of that picture.
- **The same shape was measured in H.265 before the split allocator (2026-08-26, std.video.005).** Three hot routines dumped at pre-emit, all of them
  already vectorized and already at their instruction budget on paper:
  - `Hevc.Decoder.filterLumaEdge` emits 776 instructions with **87 frame stores and 84 frame
    loads** — 22 percent of the function is stack traffic. It filters 101,633 four-line
    segments a picture at about 575 cycles each, where the instructions a segment executes
    predict something closer to a hundred.
  - `Hevc.Decoder.interpolateLuma` keeps twelve vector spills and twelve reloads inside its
    innermost body. One call filters about 800 samples in 1.73 microseconds, which is 8.6
    cycles a sample against about three from the instruction count.
  - Reading the filter taps once a block instead of once a pair removed fifteen table-pointer
    loads and twenty multiplies from the same function and **changed the measured time by less
    than one percent**, which is what says the loop is not bound by those instructions.
- **What that is worth, measured against another compiler on the same algorithm (2026-08-26)**:
  the loop filter of clause 8.7.2.5 was written twice, once in C and once in Swag, statement
  for statement, over the same synthetic 3840x2076 plane with the same thresholds and the same
  decision mix — 1,612 flat, 430,398 strong and 65,229 weak segments a picture in both. Per
  picture, best of several runs on a quiet machine:
  - clang 21 `-O2 -msse2`: **18.3 ms** (37 ns a filtered segment)
  - clang 21 `-O2 -march=native -fno-vectorize -fno-slp-vectorize`: 18.7 ms
  - clang 21 `-O2 -march=native`: 34.1 ms — **its own auto-vectorizer costs it 1.9x here**,
    which is worth knowing before reading any clang figure as the answer sheet
  - this compiler, release: **40.6 ms** (82 ns a segment)
- In that historical comparison the backend was **2.2x behind clang's best on identical scalar code**, the
  largest single factor in the 3x the H.265 decoder is behind FFmpeg — larger than the 256-bit
  forms of cpu.simd.002, and larger than anything left in the decoder's own algorithms. The frame
  traffic above is the visible half of it: 171 frame accesses in 776 instructions for one
  routine, against 61 in 443 for clang's build of the same function.
- The per-object view shipped (2026-08-26): `Pass.PostRALoopHoist` now classifies escapes per
  source object from the extents `SymbolFunction::localVariables()` carries, recognizes the
  prologue's local-base register, and keeps the two address spaces apart — a value use of the
  stack pointer (call staging) reaches sp-addressed slots, never the locals behind the base. A
  slot inside no escaped object hoists even when the frame as a whole is handed out.
- What that revealed: the pass fires only about twenty times across the whole `video` workspace,
  and in none of the hot decoder functions. The binding constraint is not aliasing any more — it
  is that a hoist needs the reload's destination register to have **no other definition in the
  whole loop body**, and after allocation every register in a fat body is reused many times.
  Post-RA hoisting cannot rename, so it is capped by the allocator's register reuse; the fix
  belongs in allocation (keep the value resident so no hoist is needed), not in a smarter hoist.
- Next: rebaseline `Hevc.Decoder.filterLumaEdge` and `Hevc.Decoder.interpolateLuma` with the now
  shipped split allocator, recording frame accesses and per-segment time. Attribute a remaining
  gap to the selected allocator or its fallback; extend the post-RA hoist only if a current dump
  first shows an invariant value with a reusable destination.
- Complete when: current dumps and alternating timings establish the remaining allocation cost
  on both large kernels and identify a specific next change or retire this lead.
- Related: compiler.optimization.024.

### compiler.optimization.015 — Extend carried-slot promotion beyond private 64-bit spills

- Recorded: 2026-08-27 07:57
- Updated: 2026-10-06 17:31 — Reuse the prologue's saved SIMD registers across calls.
- Area: compiler/backend
- Current boundary: post-allocation promotion now keeps a private 64-bit integer spill
  in a caller-saved XMM register free across a call-free loop. Every matching load/store
  becomes a register transfer; one seed precedes the header and each distinct exclusive
  exit writes the current value back. Mixed/overlapping accesses, indexed or derived stack
  addresses and changing stack pointers remain conservative barriers.
- Evidence: across 334 H.264 bodies, explicit RSP accesses fall from 2,249 to 2,213 and
  memory operations from 9,995 to 9,959, with seven extra instructions overall and no extra
  pushes. Five residualCabac instances lose 13 memory operations with unchanged instruction
  count. The 282 native optimizer, 23 H.264 and nine HEVC decoder tests pass in Release
  (JIT and native). The [rewrite and per-function tradeoffs](../bench/results/generated-code/20261006-carried-spill-cache/README.md)
  retain the structural evidence; no runtime speedup was measured.
- Extended boundary: write-only private 64-bit homes use the same cache and exit write-back
  proof. This removes the per-two-round SHA spill introduced by partial unrolling; see the
  [retained evidence](../bench/results/generated-code/20261006-partial-counted-unroll/README.md).
- Read-only homes now cross conditional calls, multiple outside entries and shared exits:
  seed every entry and restore only clobbered caches after calls. A static reuse check bounds
  the added reads. Writable homes can now cross those calls and shared exits by retaining
  their stores and updating the cache at each write. The literal-path Inflate latch loses
  its final frame reload; H.264 loses three more memory operations. The full 3,634 native,
  21 compression and 23 H.264 tests pass in Release; see the
  [write-through evidence](../bench/results/generated-code/20261006-private-write-through/README.md).
- Call-free loops with shared exits now retain coherent stores instead of being
  rejected. H.264 halfHorizontalAvg, halfCenter and buildImplicitWeights each lose
  three memory operations, with unchanged instruction and push counts. Later
  cleanup removes unobserved stores too. The other 331 bodies and CSV are unchanged;
  [comparison](../bench/results/generated-code/20261006-shared-exit-cache/README.md).
- Idle integer registers already saved by the prologue are now preferred when
  dead at every entry and untouched in the loop. A cache preserved by all calls
  also admits mandatory-call loops: H.264 extendPlane loses twelve memory accesses
  with unchanged instruction/push counts; see the
  [comparison](../bench/results/generated-code/20261006-gp-spill-cache/README.md).
- The prologue now records its actual saved SIMD registers. Idle members of that
  set also serve as caches without adding preservation traffic. H.264
  predictIntraPlane loses eleven instructions and sixteen memory operations;
  [comparison](../bench/results/generated-code/20261006-saved-xmm-cache/README.md).
- Next: inspect hot source-object slots and mixed-width spills. Removing retained
  stores from called loops needs an exit-liveness proof or edge-specific write-backs.
  Caches clobbered on every trip are still excluded, even when a home has several
  reads between calls. Any extension should prove reuse within each call-delimited
  path; counting reads on mutually exclusive arms can overstate the avoided work.
- Complete when: current codec dumps identify and resolve the remaining promotion boundary
  with aliasing, exit-path and reference-frame coverage; do not repeat the completed private
  64-bit multi-access rewrite.
- Related: std.video.005, compiler.optimization.011, compiler.optimization.020.

### compiler.optimization.034 — Reuse the selected Dijkstra heap child across its comparison

- Recorded: 2026-09-07 10:46
- Updated: 2026-10-06 16:37 — Close redundant private-global reads and isolate the selected-child reload.
- Area: compiler/backend, memory optimization
- Current evidence: the Release sift-up loop already retains its private heap
  pointers and uses eight heap memory operations on a swapping iteration.
  Function-wide value numbering now also removes redundant entry reads across
  disjoint writes: whole `push` changes from 27 instructions / 16 memory operations
  to 25 / 14, and `pop` from 43 / 28 to 39 / 24. Neither function needs a frame
  access or saved register. [Comparison](../bench/results/generated-code/20261006-heap-values/README.md).
- Remaining gap: `pop` compares both child values, selects the child index, then
  reloads the selected value. The left value is not loaded on the path where the
  right child is out of bounds, so plain forwarding is insufficient.
- Next: carry the available child value through the selection while preserving
  the one-child path, bounds, intervening alias writes and register pressure.
  The historical private-global pointer-reload diagnosis is closed.
- Complete when: the selected-child reload disappears with sound path availability,
  or a focused experiment identifies the register-residency constraint.

### compiler.optimization.035 — Improve spill choices after register and memory promotion

- Recorded: 2026-09-12 11:40
- Updated: 2026-10-06 16:03 — Isolate the remaining CSV setup allocation cost after packed promotion.
- Area: compiler/backend, register allocation and live ranges
- Evidence: after removing the permanent integer legalization reserve,
  `Slice.parsePlaneResidualCabac` gained one memory operation and
  `Slice.parsePlaneResidualCavlc` gained six plus thirteen instructions.
  The full register pool remains available; the
  [retained comparison](../bench/results/generated-code/20261006-legalize-reserve/README.md)
  owns the exact baseline.
- Additional case: promoting whole-copied locals with scalar lane reads removes
  frame traffic in ChaCha, nbody and H.264. In CSV data generation, a copied region
  string's pointer/length become GP values live across several multiplications.
  The printed bodies gain 18 instructions / 11 memory operations, 14 explicit
  RSP accesses and 64 frame bytes. The suffix from the first timing call remains
  444 instructions / 151 memory operations, and the checksum remains 24828641.
  [Allocation diff](../bench/results/generated-code/20261006-vector-lanes/csvagg-allocation.diff).
- Next: inspect splitting and rematerialization around the implicit multiply
  claims in CSV setup, and compare the two H.264 functions' interval choices.
  Preserve the extra register and legal packed promotion while correcting these
  local allocation costs. No elapsed-time regression is inferred.
- Complete when: these local increases are removed or explained by a necessary tradeoff.

### compiler.optimization.020 — Share the remaining frame alias proofs across memory passes

- Recorded: 2026-08-27 07:57
- Updated: 2026-10-06 14:54 — Share LICM and SLP privacy and retain the remaining consumers.
- Area: compiler/backend, memory alias analysis
- Current boundary: LICM and SLP consume MicroPassHelpers::analyzeFramePrivacy.
  SLP additionally checks escape reachability so an escape after a loop does not
  invalidate its earlier private-frame proof. MemToReg now reconciles direct SP
  accesses with the captured frame using shared CFG displacement facts when SP moves.
  PostRALoopHoist still owns a separate frame-object reachability model.
- Next: reconcile the post-allocation object model with the shared proof without
  losing byte-range precision, then use disjoint spaces in forwarding and value
  numbering. Inspect the four H.264 allocation changes caused by the necessary SP
  alias repair: applyMotion, deriveDirectTemporal, deriveDirectSpatial, parseSubMvs
  together add four instructions and five memory operands; preserve the repair.
- Complete when: shared facts cover those consumers, forwarding crosses a proven
  disjoint store in a real codec loop, and remaining local allocation costs are resolved.
- Related: compiler.optimization.015.

### compiler.optimization.032 — Control register pressure in wider partial unrolling

- Recorded: 2026-09-06 14:53
- Updated: 2026-10-06 11:04 — Retain two-round grouping with no hot frame traffic.
- Area: compiler/backend
- Current boundary: exact even loops too large to fully unroll can group two straight-line
  bodies, reusing the full unroller's temporary renaming and retaining counter updates and
  relocations. Calls, internal control flow and CPU-flag consumers remain outside the rule.
  Write-only private spill homes can use the existing free-XMM loop cache.
- Evidence: two SHA-256 rounds execute 95 instructions / four memory reads / zero frame
  accesses, against 100 / four / zero before. Whole main output gains 42 instructions and
  six explicit RSP accesses outside that compression loop. All seven program checksums,
  287 native optimizer tests (JIT and native), and 23 H.264 tests pass in Release. See the
  [retained code evidence](../bench/results/generated-code/20261006-partial-counted-unroll/README.md).
  No elapsed-time improvement is claimed.
- Rejected wider prototype: four rounds execute 180 instructions, including a back-edge
  register copy, and four frame stores per group. It uses three transient XMM registers
  for integer values, leaving too few for all four write-only homes. The two-round form
  needs one such home and retains zero frame traffic after the cache extension.
- Next: trace the remaining register-copy and store placement across four-round groups,
  and the six additional outer-loop frame accesses in the retained two-round form. Extend
  only with a joint allocation plan that preserves the now spill-free compression loop.
- Complete when: wider grouping reduces per-round work without reintroducing hot frame
  traffic, and the retained two-round form's outer spill cost is resolved.
- Related: compiler.optimization.005, compiler.optimization.015, compiler.optimization.016.

### compiler.optimization.022 — An inlined by-value aggregate argument is copied even when the body only reads it

- Recorded: 2026-08-28 15:42
- Updated: 2026-10-06 10:45 — Retain pure leaf array borrowing; broader bodies remain.
- Area: compiler/sema
- Found while: giving `Core.Math.Simd` its 4x4 and 8x8 transposes (2026-08-28).
- Evidence: `func transpose4x4(rows: [4] U32x4)->[4] U32x4` inlined into a caller that already
  holds the block still emitted four 128-bit loads and four stores copying the argument into a
  fresh frame slot, then read every row back out of that copy, around the eight interleaves that
  are the whole operation: 40 instructions and a 0x1C8 frame for eight instructions of work. The
  same body taking `rows: *[4] U32x4` in place compiles to 28 instructions and a 0x80 frame, which
  is what the API now does. `materializeInlineBindings` binds a by-value aggregate argument to a
  concrete local. The current `classifyInlineBinding` already examines parameter uses and can
  keep a direct binding; an indexed or foreach by-value aggregate still requires a home through
  `use.indexOrFor`, even if those uses only read. Read-only syntax alone does not establish that
  the caller's storage remains unchanged while the inlined body executes.
- Retained boundary: completed pure leaf inlines borrow a plain array from a stable caller
  variable when every argument is a same-type bare variable or constant. Parameter writes,
  addresses/buffers, captures, calls, generated source and nontrivial copy/drop types retain
  snapshots. A Release selector wrapper drops from 36 to 24 instructions and 22 to 18 memory
  operations. The [code evidence and validation](../bench/results/generated-code/20261006-inline-array-borrow/README.md)
  include alias, later-argument, callback and element-copy counterexamples; 3,631 native tests
  pass in JIT and native execution. No timing improvement is claimed.
- Next: extend the stability proof to larger/non-leaf bodies and argument evaluations that
  currently fail the conservative leaf/constant-or-variable boundary. Revisit the SIMD
  transpose with evidence from its actual caller, preserving copy/drop and alias semantics.
- Complete when: the value-returning block transform is as cheap as its in-place shape on
  the video corpus, including bodies outside the retained pure-leaf boundary.

### compiler.optimization.005 — Investigate the remaining Levenshtein outer-loop allocation costs

- Recorded: 2026-08-07 08:30
- Updated: 2026-10-06 10:16 — retire the stale SHA-256 spill diagnosis and retain the outer-loop cost.
- Area: compiler/backend
- Current evidence: Levenshtein carries both adjacent row values between iterations.
  Its inner loop has 19 instructions and three memory operations, with no frame access
  (previously 18 / five). The whole main function gains seven instructions and four
  explicit RSP accesses outside that inner loop. See the
  [retained code and validation](../bench/results/generated-code/20261006-loop-load-forward/README.md).
- Scope correction: a fresh October 6 Release listing has 50 instructions in SHA-256's
  compression round, two table/array reads and no frame accesses. All eight state values
  stay in registers after the legalization-reserve removal; its earlier `d`/`e` spill lead
  is complete. General multi-access promotion now belongs to compiler.optimization.015.
- Next: trace the four added Levenshtein frame accesses outside its inner loop and decide
  whether narrower carry residency or allocation can remove them without restoring the
  two per-iteration row reads.
- Complete when: the outer-region accesses are eliminated or attributed to unavoidable
  carry initialization/lifetime costs with the inner-loop gain preserved.

### compiler.optimization.029 — Reduce SSA rebuilding after definition-changing and redirected-use rewrites

- Recorded: 2026-09-05 22:13
- Updated: 2026-10-06 10:00 — reuse SSA dominance intervals in five optimization analyses.
- Area: compiler/backend, compilation time
- Evidence: the Sep 23 Release profile measured 300,712 SSA builds over 33,062 functions,
  about nine per function, and 7.05% of busy CPU in SSA construction. These counts predate
  current caching and convergence changes; they are a lead, not a current performance claim.
- Resolved scope: CFG identity already preserves blocks, dominators and frontiers. Operand
  refresh now also retains values, phi inputs and reaching definitions when the register
  definitions stay identical and reads only disappear. It filters each affected use list once,
  retaining operand multiplicity and visit order. Added reads, changed definitions and changed
  control flow still take the full rebuild. Comparison against freshly rebuilt SSA covers
  loops, phis, duplicate reads and fallback after a partially inspected prefix. The 1,293
  internal C++ tests and 275 native optimizer tests in Release pass. Compiler time and peak
  memory were not measured in this iteration.
- Dominance reuse: induction analysis, LICM, loop vector promotion, signed-strength reduction
  and InstructionCombine now reuse a current SSA rename tree instead of reconstructing an
  instruction-level dominator tree. CFG identity/build id and an existing rename walk are
  required; invalid states, nonzero entries and graphs without virtual definitions fall back.
  The two output interval arrays are still copied, with no additional persistent instruction
  storage. This removes graph traversal and iterative dominance construction from eligible
  queries; no compiler timing gain is claimed. The remaining definition-changing rebuilds
  described below are unchanged. The 281 native optimizer tests in Release pass, and
  [five Inflate bodies stay identical](../bench/results/compiler-work/20261006-ssa-dominance/README.md).
- Next: recheck the remaining rebuild callers at a measurement milestone. Copy elimination
  still rebuilds internally after redirecting operands, and other rewrites change definitions.
  Any further mutation contract must preserve reaching-value identities, phi edges, duplicate
  uses, and their order, including fallback when a later instruction invalidates the contract.
- Rejected evidence to retain: the Sep 16 copy-elimination alternatives replaced its internal
  rebuild with reaching-use scans or adjusted use counts plus backward phi propagation. Both
  passed focused tests, but alternating Release gui builds did not resolve a gain; both were
  discarded. Revisit with the SSA rename work, not another pass-local liveness substitute.
  Likewise, queue-time visit marking was withdrawn on Oct 4: changing depth-first priority
  can delay early exits. Keep visit order when removing duplicate work.
- Complete when: the remaining rebuild reduction preserves generated code and a repeatable
  compiler gain is resolved against the measurement floor at a later milestone.
- Related: compiler.core.004, compiler.core.030, compiler.optimization.039.

### compiler.optimization.036 — Finish shared address folding and isolate its remaining allocation cost

- Recorded: 2026-09-12 13:05
- Updated: 2026-10-06 09:18 — fold single-use address bases after vectorization and retain the local spill lead.
- Area: compiler/backend
- Resolved: late pre-allocation scheduling folds a single-use constant-offset address into
  indexed and ordinary memory operands. Cross-block candidates require an SSA proof that the
  original base remains unchanged. Frame promotion and vectorization see their original
  array shape, avoiding the earlier prototype's predictor regression.
- Evidence: the current 334-function Release H.264 cohort loses 128 instructions and 23
  memory operations. `intraPredict8x8` loses five instructions with unchanged memory-operation
  count; the five `residualCabac` instances lose 15 instructions. The 278 native optimizer
  and 23 H.264 tests pass. See the
  [retained structural evidence](../bench/results/generated-code/20261006-late-addresses/README.md).
- Remaining: `Slice.parsePartitions` gains three instructions and two memory operations.
  Shared addresses, including the context-array base used through several copies in
  `residualCabac`, remain outside the single-use rule. A source dump before `sink-to-use`
  shows the base at Slice + 0x98 feeding four copies rather than one memory operand.
- Next: attribute `parsePartitions`' new spill choice, and consider shared-base substitution
  only when every use preserves the base and removing the address does not extend pressure.
  Keep the late stage so array promotion/vectorization retain their input shape.
- Complete when: the local allocation cost is resolved or explained and profitable shared
  address cases have a bounded all-use proof.

### compiler.optimization.105 — Prove lz77's signed remainder bounds

- Recorded: 2026-09-30 08:42
- Updated: 2026-10-06 08:54 — remove the resolved XMM index transfer from the remaining LZ77 scope.
- Area: compiler/backend, value ranges and signed remainder lowering.
- Comparison: accepted campaign `20261001-103647` names Zig 0.15.2 `ReleaseFast` as the
  fastest other runtime at 19.9267 ms, versus Swag native at 21.3543 ms. Its candidate
  loop has 29 non-NOP instructions and three actual memory accesses; its byte-match
  loop has six instructions and two reads. Swag now matches those counts after
  caching the invariant index in an otherwise unused caller-saved SIMD register.
  The latch transfers its bits back to a GP register; one seed load runs before
  the loop. These static changes have not been timed in a new full campaign.
- Remaining evidence: `cand % WINDOW` is already a mask, justified by `cand >= 0`.
  Swag's signed `i` and `p` remainders retain sign correction. Zig uses `@mod`, whose
  floor-modulo result for a positive power-of-two divisor permits masking even for
  negative inputs; Swag's signed remainder has a different contract. The previously
  inspected C++/Clang 20.1.8 winner also retained sign correction. Simplifying Swag's
  remaining remainders requires proving the counters' bounds under its own semantics.
- October 3: an unsigned remainder by a constant whose dividend is bounded multiplies by a
  dword magic number, so the checksum loop `hc = (hc * 31 + comp[k]) % 1000003` has 12
  instructions instead of 18 and a carried chain of about 12 cycles (clang's two-way unrolled
  loop takes about 13 per element). Paired lz77 medians were 0.961 in two controlled windows;
  the second window's spread overlaps its unchanged-binary control.
- Rejected on October 3, measured with an unchanged-binary control on a quiet machine (41 to
  61 rounds), each rule alone on master `1898124b1`:
  - Byte and word loads whose upper bits are dead as `movzx` (`2b23c932f` on
    `perf/prompt2-int-20261003`): lz77 0.998 against a 0.999 control, and fannkuch 1.046 and
    1.050 in two windows against 1.003: its main loop is byte-identical but sits 0x50 bytes
    later because each `movzx` is one byte longer, moving the flips loop within its cache line.
  - A multiplication by 2^n+1 or 2^n-1 as a shift and an add or subtract (`27ef513e8`, same
    branch): every task inside its control spread (lz77 1.003).
  - Post-RA copy forwarding through indexed loads (`aacbe30d8` on
    `perf/prompt2-int-lot3-20261003`): the candidate loop loses
    `mov rax, [rsi + 8 * r10]; mov r10, rax` (19 to 18 instructions) and 10 to 15 copies go
    per executable, but lz77 is 1.000 against a 1.005 control; the core renames such moves away.
- October 6: removing the legalization reserve keeps the invariant index in an integer
  register and removes its XMM2 transfer on each candidate. Main loses eight instructions
  and seven memory operations. The `l < limit` guard before the byte loop still remains
  where clang proves `n - i >= 4`.
- Next: follow the loop-carried counters through SSA ranges and exit conditions.
  Establish nonnegativity before replacing sign correction; retain negative-input
  controls and do not infer a bound merely from this benchmark's current inputs.
- Complete when: each removable sign correction has a sound range proof, exact
  checksums and unrelated positive/negative coverage, with the candidate and byte
  loops retaining their instruction and memory counts without a loss elsewhere.

### compiler.optimization.039 — Locate the remaining optimization sweep-budget outliers

- Recorded: 2026-09-16 12:12
- Updated: 2026-10-06 07:49 — reduce expectedCountOnes16 from twenty Release sweeps to six.
- Area: compiler/backend, compilation time
- Evidence: the pre-RA loop has a twenty-four-sweep cap. The Sep 30 standard-module test
  campaign found a 404-instruction `#test` at that cap; its current source identity and
  convergence still need to be recovered. The other known outlier, `expectedCountOnes16`,
  now takes six Release sweeps instead of twenty, with the same 99 final Micro instructions.
  Constant folding follows scaled address chains in one run; select narrowing walks queued
  candidates backwards and uses only already accepted narrow-reader rewrites. The Release
  optimizer selection passes 275 tests, including every u16 input and wrapping mask chains.
  No compiler timing or memory comparison was made in this iteration.
- Next: identify the remaining 404-instruction test during a standard-module validation
  milestone, check whether it shares either resolved chain, and fix or bound its next blocker.
  Do not repeat the completed constant-address or select-width chain work.
- Complete when: no standard-module function, tests included, needs more than sixteen sweeps,
  or each longer chain is identified and bounded.
- Related: compiler.optimization.029, compiler.core.004.

### compiler.optimization.125 — Finish the AVX boundary cost and caller-state audit

- Recorded: 2026-10-05 17:55
- Updated: 2026-10-06 07:37 — consistently encode XMM operations with VEX and narrow the remaining audit.
- Evidence: native, JIT, foreign-return and callback dirty-state probes now match clean-state
  numerical results and performance. Release dirty-state nbody falls from about 23 ms to 0.17 ms.
  Ordinary Release sentinels do not establish a general speedup or a reproducible regression;
  retain both measurement windows in the [evidence](../bench/results/generated-code/20261006-avx-vex/README.md).
- Next: at a later measurement milestone, check compiler cost and establish which AVX state
  reaches the unmodified benchmark from the Oct 5 investigation. The boundary fix does not
  establish the cause of that historical timing change. Do not repeat the completed encoding work.
- Complete when: the unmodified caller-state question is resolved and compiler cost is assessed.
- Related: compiler.optimization.121, cpu.simd.001.

### compiler.optimization.121 — Optimize final code and data layout with retained structure

- Recorded: 2026-10-04 16:08
- Updated: 2026-10-05 17:55 — retain the reproduced layout regression and the unaccepted alignment candidate.
- Evidence: local cold-block placement and loop alignment exist; the integrated linker owns final
  symbols/relocations. It can retain function/block boundaries and profile edges instead of
  reconstructing them from an executable.
- Regression evidence: the Oct 5 allocator investigation reproduces a 7.14% DevMode
  `fannkuch` loss against the rebuilt old revision, with unchanged normalized hot instructions.
  The main moves from RVA `0xaee0` to `0xafd0`. Candidate `5d3338007` stabilizes alignment
  modulo 32 and passes functional tests, but remains off master: the final quiet 32-round
  subset improves DevMode `fannkuch` by 5.10% while slowing DevMode `binarytrees` by 4.50%
  (unchanged-binary control +0.07%). Blanket alignment does not meet the performance gate.
  A contiguous-order experiment was removed. The candidate grows executable size by 1.28%
  and text by 3.32% in median. See the [evidence and identities](../bench/results/generated-code/20261005-runtime-layout/README.md).
- Next: investigate selective alignment and repeat independent quiet blocks across native
  execution, compiler time/memory, and binary size with unchanged-binary controls. Then retain
  layout metadata through object/cache boundaries and reorder functions by weighted
  call locality with deterministic static fallback. Measure instruction-cache behavior and binary
  size before expanding to block splitting or data placement.
- Expansion: global hot/cold separation, constants near consumers, final-size/profile-aware
  alignment, and eligible branch relaxation/re-encoding once distances are known. Respect
  displacement limits and identity constraints; allow bounded feedback when final sizes change
  earlier profitability estimates.
- Output: update relocations, debug ranges/inline provenance, unwind/exception records, runtime
  symbol tables, and cached offsets together. Keep target-specific restrictions behind backend
  interfaces; deterministic placement needs stable global-data identities too.
- Elsewhere: [BOLT](https://github.com/llvm/llvm-project/blob/main/bolt/README.md) demonstrates
  profile-guided post-link layout. Its ELF implementation is a design reference, not a drop-in
  replacement for Swag's PE backend.
- Complete when: large modular consumers have reproducible valid images and measured locality gains,
  stack-walking/debug fixtures pass, unprofiled builds retain useful placement, and runtime, size,
  startup, and build costs are evaluated separately.
- Related: compiler.optimization.118, compiler.optimization.119, compiler.optimization.120,
  compiler.core.074.

### compiler.optimization.107 — Preserve resolved bodies before ABI lowering

- Recorded: 2026-10-04 16:08
- Updated: 2026-10-04 18:18 — Distinguish automatic inline eligibility from the shared static-storage guard.
- Evidence: ordinary inlining clones and re-analyzes syntax in `SemaInline.cpp`. Automatic selection
  excludes generic and fallible functions and most aggregate signatures; all ordinary inline modes
  reject bodies declaring static storage.
  [CodeGenCallHelpers.Call.cpp](../src/Compiler/CodeGen/Core/CodeGenCallHelpers.Call.cpp) assigns
  concrete argument registers/stack slots through `ABICall::prepareArgs` before Micro passes.
- Next: prototype an immutable, typed, serializable scalar body with calls, parameters, returns,
  memory objects, and symbolic globals above the ABI. Compare a frozen resolved-body representation
  with a compact new IR on size and lowering cost; select the smallest correct design.
- Scope: stable symbol/type identities, control flow, explicit effects, source provenance,
  configuration, and ownership/cleanup/error edges. Private helpers remain compiler-visible without
  becoming source-public. Cloned function-local globals/TLS still refer to their original storage.
- Expansion: preserve generic-instance identity, moves/copies/drops, `defer`, fallible returns,
  nullable facts, receivers, closures, and variadics before admitting each shape. Macros/mixins and
  compile-time constructs retain their semantic expansion rules; optimize their resolved runtime
  result without replaying expansion in the consumer.
- Complete when: body round trips and cross-module cloning preserve behavior and locations, static
  storage has one identity, unsupported shapes fall back cleanly, and existing Micro lowering
  consumes bodies without a second semantic analysis of ordinary function syntax.
- Related: compiler.optimization.106, compiler.optimization.108.

### compiler.optimization.123 — Generate profitable CPU variants across source modules

- Recorded: 2026-10-04 16:08
- Updated: 2026-10-04 18:18 — Keep optional-feature dispatch with cpu.simd.001 and bound the intermodule variant work.
- Evidence: a final application may target a known CPU or a baseline with optional extensions.
  Source-visible dependency kernels can follow the same target policy as their callers instead of
  being limited to a separately built library's instruction selection.
- Next: prove consistent fixed-target propagation through imports/caches/specialized callees,
  then prototype two measured kernel variants behind one baseline-safe dispatcher. Select kernels
  by cost/profile evidence instead of cloning whole dependencies.
- Boundary: reuse the optional-feature query and dispatch contract owned by cpu.simd.001; this
  entry owns variant generation and reuse across source-module boundaries.
- Scope: account for OS-enabled vector state as well as CPU features; isolate unsupported
  instructions behind the guard; hoist dispatch outside hot loops when stable. Preserve canonical
  exported/address-taken identity, unwind, and debug behavior.
- Policy: bound variant count and code growth, key profiles/caches by feature sets, and omit dispatch
  for fixed-target builds. This is ahead-of-time multiversioning; deploying the compiler's JIT
  inside applications would require a separate runtime/deployment decision.
- Complete when: a third-party kernel has a measured faster variant on supporting hardware, the
  baseline runs on the declared minimum target, dispatch is correctly gated/amortized, and build
  cost plus artifact growth justify the chosen variants.
- Related: compiler.optimization.109, compiler.optimization.112, compiler.optimization.120,
  cpu.simd.001.

### compiler.optimization.106 — Resolve local implementations and optimization boundaries

- Recorded: 2026-10-04 16:08
- Updated: 2026-10-04 16:18 — Identify the existing dependency snapshots and the API/native publication handoff.
- Evidence: `shouldAutoInline` in
  [SemaInline.cpp](../src/Compiler/Sema/Helpers/SemaInline.cpp) rejects another module namespace.
  [ModuleApiExport.Generate.cpp](../src/Compiler/ModuleApi/ModuleApiExport.Generate.cpp) normally
  publishes ordinary functions as `Foreign` declarations and preserves explicit inline bodies.
  A source installation alone therefore does not supply an optimization body.
- Resolution seam: `DependencyPlanBuilder::resolveNode` in
  [CompilerInstance.Module.cpp](../src/Main/CompilerInstance.Module.cpp) already captures API bytes
  under `ModuleApi::DirectoryAccess`, retains original artifact paths in `sourcePaths`, and records
  consumer mirror paths separately. `ModuleSetupInputApplier` selects static/shared linkage for
  the actual closure. Extend that resolved graph rather than adding a second module search.
- Next: prototype a provider mapping the selected module/function identity to its exact immutable
  implementation and build contract. Compare in-process handoff for sibling modules with a
  published descriptor/body store for independently built packages. Prove both through two local
  workspaces and an unannotated scalar helper before expanding the supported body shapes.
- Publication: `exportModuleApi` publishes before native generation; deferred linking can overlap
  compilation of the next module. Freeze the API/body generation together, then certify its match
  to the selected artifact at native publication/link consumption. A later reread of a source path,
  a matching module name, or unchanged size/timestamps is insufficient. Do not introduce a mandatory
  native-link barrier before consumers can analyze bodies; final binding must validate assumptions
  or discard/recompile affected variants before emitting the image.
- Scope: track source/IR availability, implementation identity, binding stability, external visibility,
  address escape, and whether all callers are known as separate facts. Distinguish a Swag import
  lowered through `Foreign` from an opaque external implementation without changing its ABI.
  Cover transitive imports, overrides, multiple versions, generated sources, and read-only packages.
  Resolve the dependency selected by the build; do not scan unrelated files or fetch missing source.
- Fallback: absent/incompatible optional optimization material keeps the ordinary verified artifact
  path. A source/binary mismatch must never optimize one implementation while linking another;
  use normal rebuild policy or decline the optimization.
- Regression matrix: source/API/artifact edits with preserved sizes and timestamps; interrupted and
  concurrent publication; original versus mirrored dependency paths; relocated read-only packages;
  the same module name at different versions; and shared/static alternatives of one dependency.
  Capture generated and compile-time-dependent implementation context through the build model;
  source-file hashes alone cannot reconstruct a resolved body or authorize its reuse.
- Complete when: equivalent local, vendored, and third-party implementations expose equivalent
  eligible bodies; mismatched and opaque imports stay correct; shared exports retain their required
  binding; decision records identify the exact eligibility reason.
- Related: compiler.optimization.107, compiler.optimization.109.

### compiler.optimization.108 — Build a bounded global call index and optimization driver

- Recorded: 2026-10-04 16:08
- Evidence: [MicroPassManager.cpp](../src/Backend/Micro/MicroPassManager.cpp) operates on individual
  functions; semantic automatic inlining has a limited call graph; the linker resolves emitted
  symbols. These are not a general selective importer and interprocedural transformation driver.
- Next: summarize identities, cost, direct edges, possible indirect targets, address uses, visibility,
  and referenced data. Resolve a combined index for the actual link closure and import only selected
  bodies. Analyze recursive strongly connected components with conservative fixed points.
- Algorithm: publish completed immutable facts, use change-driven worklists and explicit widening/
  budgets, and reschedule only affected functions. Revisit reachability after graph changes.
  Alternate specialization, devirtualization, inlining, and local simplification in bounded rounds,
  then lower ABI and run Micro. Separate proof facts from profitability estimates.
- Scheduling: parallel independent partitions under a memory budget, evict unused imports, and use
  stable work ordering and deterministic budget allocation. Avoid semantic wait cycles and
  publication barriers that require every dependency to finish native linking first.
- Elsewhere: [ThinLTO](https://clang.llvm.org/docs/ThinLTO.html) combines compact summaries, selective
  function importing, parallel backends, and incremental reuse.
- Complete when: recursive, diamond, and large sparse graphs converge deterministically with bounded
  imported memory; newly direct/dead edges trigger targeted reanalysis; unrelated partitions stay
  reusable; instrumentation accounts for time and memory by phase.
- Related: compiler.optimization.107, compiler.optimization.109, compiler.core.073.

### compiler.optimization.109 — Cache bodies and the assumptions used by callers

- Recorded: 2026-10-04 16:08
- Evidence: [NativeBackendBuilder.cpp](../src/Backend/Native/NativeBackendBuilder.cpp) fingerprints
  Micro for its native function cache and currently excludes bodies with relocations. Importing
  implementations creates dependencies that public API fingerprints alone cannot describe.
- Next: define separate immutable caches for typed bodies/summaries and native variants. Key variants
  by body, referenced types/constants, compiler/IR schema, target/CPU, semantic configuration,
  optimization policy, and relevant profile identity.
- Dependencies: track imported private bodies, propagated effects/value facts, specialized arguments,
  binding resolution, and devirtualization assumptions. Include negative/global facts: adding a
  target or caller may invalidate uniqueness or all-callers proofs without changing an old body.
- Publication: content-addressed records, atomic completion, schema rejection, concurrent readers,
  cancellation-safe writes, and consumer-owned writable caches for read-only packages. Logical
  identity should allow harmless path relocation without confusing distinct builds. Track generated
  and compile-time inputs through the build model; untracked environmental dependencies prevent reuse.
- Complete when: private edits invalidate affected callers/variants, unrelated edits retain hits,
  target/configuration/summary/profile changes cannot reuse stale code, and interrupted concurrent
  builds cannot publish partial artifacts. Measure cold, warm, and edit/rebuild costs separately.
- Related: compiler.optimization.106, compiler.optimization.108, compiler.core.030.

### compiler.optimization.110 — Infer interprocedural memory and value summaries

- Recorded: 2026-10-04 16:08
- Evidence: `SymbolFunction` already carries borrow/escape/release summaries; API publication exports
  `BorrowSummary` and `ReadOnly`; LICM and selected post-allocation passes consume direct readonly
  calls. Extend this foundation instead of introducing a separate incompatible effect system.
- Next: summarize reads/writes by parameter-derived/global region, capture, allocation/release,
  ambient-state access, callback effects, and return ranges/nullability/alignment/argument relations.
  Compute transitive facts over recursive components and serialize them with their body/configuration.
- Consumers: preserve facts through calls in value numbering, load/store elimination, LICM, and
  range propagation. Unknown external/indirect behavior remains unknown. Keep noncapture, readonly,
  purity, no-alias, termination, and failure distinct; model atomics, volatile accesses, TLS/context
  mutation, aliasing, and reentrant callbacks.
- Proof: deleting an unused call also needs termination/error and other observable effects to permit
  removal; readonly alone is insufficient. Reuse existing borrow proofs where their meaning matches,
  without treating a lifetime guarantee as a stronger alias guarantee.
- Complete when: a third-party readonly helper preserves an unrelated load without being inlined;
  transitive writers/callbacks invalidate it; recursion converges; summary-only imports help callers
  even when their bodies are not imported.
- Related: compiler.optimization.108, compiler.optimization.109, compiler.optimization.055,
  compiler.optimization.020.

### compiler.optimization.111 — Inline ordinary functions across module boundaries

- Recorded: 2026-10-04 16:08
- Evidence: the namespace guard in `shouldAutoInline` in `SemaInline.cpp` prevents automatic
  intermodule inlining. Its signature/body exclusions are correctness boundaries; deleting the guard
  or marking every export `Inline` does not implement general importing.
- Next: inline resolved unannotated scalar/pointer direct callees from any eligible module using
  typed bodies. Fold caller constants and simplify immediately, then expand supported shapes with
  focused regression coverage.
- Cost model: estimate residual work after substitution, loop depth/frequency, duplicated code,
  register pressure, frame growth, and downstream vectorization. Bound total caller growth,
  recursion, imported bytes, and compilation work. A single-caller bonus requires proof that the
  final call/body can disappear; share growth budgets with unrolling.
- Semantics: retain effective callee contracts, evaluation order, cleanup, and unique storage.
  Preserve canonical bodies for remaining calls/observed addresses. Honor `Never` and `NoInline`;
  define interaction with explicit `Inline` without incidentally changing its semantics.
- Complete when: profitable unannotated helpers and private helper chains in unrelated packages
  inline automatically, forbidden/oversized cases remain calls, and runtime, size, compile-time,
  and memory results justify the default policy. Import visibility never changes source validity.
- Related: compiler.optimization.107, compiler.optimization.108, compiler.optimization.110,
  compiler.core.071, compiler.optimization.022.

### compiler.optimization.112 — Specialize ordinary calls on constants and known callbacks

- Recorded: 2026-10-04 16:08
- Evidence: separately compiled functions lose call-site constants and callback identities. Existing
  generics and constant folding do not constitute a general intermodule residual-function pipeline.
- Next: clone an ordinary function for a proven constant scalar/enum/mode argument, simplify it,
  and redirect eligible calls without requiring generics in source. Extend to lengths, alignment,
  known callback targets, and profitable type/context facts.
- Sharing: intern semantic specialization keys so callers reuse variants. Propagate through wrappers
  and recursive components with bounded variant counts; preserve a general version where needed.
  Never duplicate a static/TLS object along with a cloned body.
- Policy: charge growth/work to the shared driver budgets. Profile-frequent values require a guard
  and general fallback; proven constants do not. Avoid cloning for large or rare constant domains.
- Elsewhere: [GCC interprocedural options](https://gcc.gnu.org/onlinedocs/gcc/Optimize-Options.html)
  describe constant propagation and cloning.
- Complete when: consumers share useful mode-specific variants with dead branches removed, known
  comparators become direct calls, general callers remain correct, and bounded clone families show
  measured value beyond merely removing call instructions.
- Related: compiler.optimization.109, compiler.optimization.110, compiler.optimization.111,
  compiler.optimization.120.

### compiler.optimization.113 — Devirtualize interfaces, callbacks, and stable context regions

- Recorded: 2026-10-04 16:08
- Evidence: `SemaInline::tryInlineCall` leaves dynamic interface dispatch intact. Global value flow
  can establish targets more precisely than an interface type; local source availability alone does
  not prove a closed implementation set.
- Next: track function/interface targets through construction, assignment, parameters, returns, and
  closures, then replace proven singleton targets with direct calls across modules. Preserve receiver
  adjustment, capture layout, lifetime, and canonical function identity.
- Expansion: identify regions with a stable allocator, writer, comparator, or other interface value,
  using context read/write summaries. Specialize their call chains for that proven context; stop at
  mutation, unknown callbacks/reentrancy, or external escape.
- Boundaries: exported interfaces, plugins, shared libraries, and unknown FFI callbacks retain
  open-world behavior. Profile-dominant targets may get guarded fast paths with complete fallbacks;
  frequency never proves that other targets are impossible.
- Elsewhere: [LLVM WholeProgramDevirt](https://llvm.org/docs/doxygen/WholeProgramDevirt_8cpp_source.html)
  demonstrates whole-program virtual-call reasoning.
- Complete when: a third-party interface pipeline becomes direct where proven, dynamic implementations
  still work, new reachable targets invalidate cached proofs, and context mutation/reentrancy defeats
  invalid region specialization.
- Related: compiler.optimization.108, compiler.optimization.110, compiler.optimization.112.

### compiler.optimization.114 — Specialize aggregate transport and internal signatures

- Recorded: 2026-10-04 16:08
- Evidence: compiler.optimization.022 owns a local aggregate-copy gap. Cross-module body/use
  information additionally permits changing internal calls instead of transporting the entire
  public ABI representation.
- Next: create an internal worker taking only needed scalar fields and returning consumed values;
  keep a canonical ABI entry for external/indirect/unrewritten calls. Apply argument promotion,
  unused-argument elimination, return decomposition, and caller return-storage reuse.
- Proof: preserve by-value snapshots under alias writes, argument effects, copy/drop hooks, moves,
  failures, and address identity. Unused result fields do not authorize removing observable work.
  Materialize objects whose address, layout, or whole-object operations remain observable.
- Expansion: scalarize short-lived aggregates through module boundaries and feed existing
  memory-to-register/vectorization passes. Keep the existing local copy-materialization entry as
  the owner of that defect rather than duplicating its work here.
- Complete when: eligible third-party aggregate round trips lose redundant copies/hidden return
  storage, external wrappers retain their ABI, and alias/lifecycle regressions prove value semantics.
  Report throughput, frame size, and code size.
- Related: compiler.optimization.107, compiler.optimization.110, compiler.optimization.022.

### compiler.optimization.115 — Eliminate proven temporary allocations across calls

- Recorded: 2026-10-04 16:08
- Evidence: borrowing, escape, release, and ownership analysis already exists; imported bodies can
  expose producer/consumer lifetimes hidden by module calls. Nonescape alone does not permit
  suppressing allocations with observable behavior.
- Next: choose one temporary with bounded size/lifetime and matched cleanup; prove scalar replacement,
  stack placement, or construction directly into consumer storage. Start with existing contracts.
- Proof: preserve allocator hooks, allocation failure behavior, finalization, address comparisons,
  alignment, provenance, and diagnostics required by the configuration. Custom allocators may
  observe every operation. If current semantics lack the necessary freedom, first decide a narrowly
  scoped explicit contract rather than silently changing those semantics.
- Expansion: eliminate redundant ownership transfers/copies along the same lifetime and fuse
  construction/consumption where effects allow it. Bound stack growth; reject unbounded promotion.
- Complete when: an ordinary dependency pipeline loses a measured temporary allocation while escapes,
  observable allocators, failures, and cleanup ordering retain their behavior. Report allocation count,
  stack footprint, compilation cost, and runtime.
- Related: compiler.optimization.110, compiler.optimization.113, compiler.optimization.114.

### compiler.optimization.116 — Carry intermodule proofs into loop and vector optimization

- Recorded: 2026-10-04 16:08
- Evidence: Micro already has LICM, induction analysis, unrolling, and SLP. Existing leads identify
  lost alias/range facts; imported bodies can expose simpler loops and stronger facts to these passes.
- Next: propagate proven lengths, strides, alignment, disjoint regions, and return ranges through
  calls. Remove repeated enabled guards, hoist stable memory, simplify induction, and expose
  vectorizable work after specialization/inlining.
- Expansion: investigate bounded loop unswitching, runtime alias/alignment versioning, loop
  vectorization, and producer/consumer loop fusion where dependence/effect proofs permit. Keep the
  general path when a runtime precondition fails; coordinate growth with inlining and unrolling.
- Semantics: respect signed arithmetic/overflow, configured FP behavior, traps/error order, zero-trip
  loops, atomics, and observable memory. This work does not change safety-guard defaults.
- Complete when: loops crossing third-party helper boundaries retain facts and gain demonstrated
  optimization; overlap, changing lengths, overflow, and guarded fallback cases remain correct.
  Existing local gaps remain with their existing entries.
- Related: compiler.optimization.110, compiler.optimization.111, compiler.optimization.112,
  compiler.optimization.020, compiler.optimization.105, compiler.safety.008.

### compiler.optimization.117 — Inline fast paths while sharing cold continuations

- Recorded: 2026-10-04 16:08
- Evidence: `MicroColdBlockLayoutPass` already moves selected cold blocks within functions.
  Whole-body inlining can still duplicate refill/allocation/error paths; rejecting the whole body
  also loses profitable small fast paths.
- Next: identify a cheap guard/hot body plus a cold continuation, outline the continuation into a
  shared worker, and inline only the profitable part across modules. Start from structural evidence,
  then incorporate profile weights.
- Contracts: preserve live-in/live-out values, stack/borrow lifetimes, cleanup ownership, error
  edges, and source locations. Keep call/return and unwind behavior valid; avoid charging the hot
  path for cold-only frame/register requirements where feasible.
- Cost: account for new marshaling/spills as well as saved bytes. Share equivalent continuations
  only when state, effects, and identity permit.
- Complete when: a package-local refill or checked-operation pattern gains an inlined fast path
  and one correct shared slow path, measured growth is bounded, and failure/cleanup/stack-walking
  coverage remains green.
- Related: compiler.optimization.111, compiler.optimization.114, compiler.optimization.120.

### compiler.optimization.118 — Use precise callee register contracts for internal calls

- Recorded: 2026-10-04 16:08
- Evidence: `ABICall`, `CallConv`, and register allocation represent concrete ABI register effects.
  A known direct implementation may clobber fewer registers than its ABI permits, even when
  inlining is undesirable.
- Next: publish actual callee clobber masks after lowering, including transitive calls, and retain
  caller values in proven preserved registers. Lower acyclic callees first; use conservative fixed
  points or the ordinary ABI inside recursive components.
- Expansion: measure internal worker conventions with argument/result placement chosen for a call
  cluster, redundant save/restore removal, and legal sibling/tail calls. Preserve platform unwind
  requirements and canonical ABI entries for external/indirect/address-taken uses.
- Stability: invalidate callers when contracts change, avoid allocation oscillation, and do not
  infer preservation through unknown calls, instrumentation, or patchable targets. Bound the
  compilation serialization introduced by bottom-up lowering.
- Elsewhere: [GCC interprocedural register allocation](https://gcc.gnu.org/onlinedocs/gcc/Optimize-Options.html#index-fipa-ra)
  exploits registers known not to be clobbered by callees.
- Complete when: noninlined third-party helpers permit fewer caller spills under verified contracts,
  recursive/opaque cases remain sound, and runtime savings justify code-size and scheduling costs.
- Related: compiler.optimization.108, compiler.optimization.109, compiler.optimization.114.

### compiler.optimization.119 — Recompute whole-image liveness after specialization

- Recorded: 2026-10-04 16:08
- Evidence: `partitionArchiveObjects` already emits one function/read-only allocation per archive
  member; `PELinker::resolveSymbols` extracts demanded members and folds some identical functions/
  data. Transformations can create new dead code/data and reveal equivalence before machine emission.
- Next: define complete artifact roots and recompute reachability after graph-changing passes,
  before emission and when binding changes the graph. Include entry points, exports, initializers,
  address uses, callback registrations, interface tables, runtime type information, TLS, and
  explicitly retained symbols.
- Expansion: omit unreachable bodies, data, and metadata edges; remove initialization only when
  its effects permit; recover granularity where unrelated writable globals share an object.
  Evaluate semantic merging of specialized/generic bodies beyond byte equality while preserving
  observable function/data addresses and mutable-storage identity.
- Boundaries: reflection and dynamic lookup contribute roots under their actual contracts.
  Unknown external behavior stays conservative. Debug provenance must not unnecessarily retain
  executable code, and unused globals do not imply effect-free initializers.
- Complete when: specialized third-party features lose their unused implementation/data closure,
  registered callbacks and reflection survive, initialization order/effects remain correct, and
  text/data/startup gains are measured against the existing linker.
- Related: compiler.optimization.108, compiler.optimization.112, compiler.optimization.113.

### compiler.optimization.120 — Collect and consume stable application profiles

- Recorded: 2026-10-04 16:08
- Evidence: no general profile-feedback pipeline was found in the inspected optimization/linking
  paths. Call frequency, branch bias, and target/value distributions can distinguish profitable
  specialization from harmful code growth.
- Next: implement end-to-end function/call/branch instrumentation with stable logical identities,
  including imported/inlined origins. Define versioning, merging, saturation, workload weighting,
  and matching to compiler/configuration/body identity.
- Expansion: bounded indirect-target and useful value histograms, followed by a separate assessment
  of sampling import on supported platforms. Attribute counts through cloning/inlining/outlining
  without double counting or applying old binary addresses to a new layout.
- Consumption: feed inlining, specialization, devirtualization, loop decisions, and cold paths.
  Missing/partial/stale profiles fall back predictably with decision records. Profiles guide
  profitability; they never prove an unobserved branch/target impossible.
- Complete when: training and held-out workloads show repeatable benefit, collection overhead and
  storage are measured, profile changes correctly affect variants/caches, and unprofiled or changed
  dependencies compile correctly.
- Related: compiler.optimization.109, compiler.optimization.112, compiler.optimization.113,
  compiler.optimization.117.

### compiler.optimization.122 — Partially evaluate dependency code and freeze eligible data

- Recorded: 2026-10-04 16:08
- Evidence: Swag already has compile-time execution and purity analysis. Imported resolved bodies
  could extend constant reasoning to ordinary functions with partly static inputs without explicit
  compile-time annotations at every call.
- Next: reuse typed-body evaluation for bounded pure computations with known inputs, or residualize
  partly known computations into smaller runtime bodies. Do not replay module setup or execute
  arbitrary effectful dependency code while trying an optimization.
- Expansion: precompute deterministic dispatch/parsing tables, immutable initialization, and
  schema/format-dependent work when inputs and target behavior are known. Keep data relocatable
  and shareable; host-process pointers are not target-program addresses.
- Proof: preserve observable I/O/state, nondeterminism, allocation effects, and failure timing.
  Respect target integer/FP semantics and configuration. Bound steps, recursion, memory, and output
  size; exhaustion retains the runtime computation.
- Complete when: ordinary third-party computations lose proven static work, partial inputs yield
  bounded reusable residual bodies, host/target differences are respected, and unsupported/effectful/
  expensive computations reliably remain at runtime.
- Related: compiler.optimization.107, compiler.optimization.110, compiler.optimization.112,
  compiler.optimization.119.

### compiler.optimization.124 — Evaluate private data representation specialization

- Recorded: 2026-10-04 16:08
- Evidence: global use/escape facts can expose internal data, but source availability alone does
  not allow changing Swag layout, reflection, addresses, or serialized representations. This is
  an exploratory outcome after the shared proof infrastructure.
- Next: inventory representation-observing operations and select one workload with known producers/
  consumers. Compare field elimination, hot/cold splitting, compact tags, or array-of-structures
  to structure-of-arrays conversion; prototype one only after establishing legality and expected value.
- Proof: account for offsets, size/alignment queries, pointer arithmetic/casts, whole-object copies/
  comparisons, reflection, serialization, FFI, debug inspection, concurrency, and identity. Preserve
  observed representation or establish a correct boundary conversion. Do not silently redefine
  ordinary public/source-observable types.
- Decision: determine whether current semantics admit useful cases or a narrowly scoped explicit
  representation-freedom contract is needed. Any language/API change follows its own syntax,
  documentation, and compatibility workflow; this plan does not preselect one.
- Complete when: the investigation delivers a legal measured prototype and bounded implementation
  decision, or establishes why the benefit does not justify the required semantic freedom.
  Speculative transformations must not become default behavior without that evidence.
- Related: compiler.optimization.110, compiler.optimization.114, compiler.optimization.115,
  compiler.optimization.119.

### compiler.optimization.094 — Defer callee-saved XMM traffic past an early exit

- Recorded: 2026-09-28 09:58
- Updated: 2026-09-30 19:55 — Closed the focused round with retained-code validation.
- Area: compiler/backend, register allocation, prologue and unwind information
- Evidence: The latest accepted campaign (`20260928-105618`) names C++/MSVC as raytrace's fastest other runtime (9.249 ms versus Swag's 10.469 ms; ratio 1.132). In `trace`, Swag saves XMM6–XMM15 before its first `intersect` call and reloads all ten on the no-hit return. MSVC saves six XMM registers before that call; after `g_HitI >= 0` it saves XMM9 and XMM13–XMM15, which the no-hit path never touches. The no-hit path therefore avoids four stores and four loads in MSVC. Swag's frame reserves `0x168` bytes and MSVC's `0x128`, though allocation size alone does not measure the path cost.
- Unwind evidence: `dumpbin /unwindinfo` on the accepted MSVC executable shows a primary `trace` range `0x1440–0x14DA` with six `SAVE_XMM128` records and a chained range `0x14DA–0x16F0` with saves for XMM9/XMM13/XMM14/XMM15 plus RBX/RDI. The no-hit return at object offset `0x74` lies in the primary range; the four later saves begin at offset `0xB4`. Two further chained ranges describe later control-flow regions. Swag currently builds one `UNWIND_INFO` blob in `X64UnwindWindows`, one native `.pdata` entry per function in `DebugInfoCodeView`, and one JIT `RUNTIME_FUNCTION` per allocation in `Os.Windows`. Those three interfaces must represent multiple code ranges before a delayed save can be correct under Windows unwinding.
- Contract: [Microsoft's x64 unwind specification](https://learn.microsoft.com/en-us/cpp/build/exception-handling-x64?view=msvc-170#chained-unwind-info-structures) permits chained code regions for delayed register saves, but excludes an additional push or fixed stack allocation in the delayed region. The save slots must therefore remain in the entry frame. The encoder currently closes unwind tracking after the first ordinary instruction, while `MachineCode` exposes a single unwind byte array; `DebugInfoCodeView::appendUnwindSections` writes one `.pdata` record, and `Os::addHostJitFunctionTable` registers one runtime range. `PrologEpilogSanitize` also shares identical return tails, so the early and hit exits must carry the right saved-register state after that rewrite.
- Binarytrees audit (Node 20.15.1 winner in `20260930-152655`): the retained `check`
  is 25 instructions/three memory operands, including two pushes and two pops (excluded
  from the memory-operand count). A leaf still pays the prologue and restores. Delaying that work across the first null guard is not a local
  peephole: the current single unwind range cannot describe the leaf's different frame.
- Rejected short-tail sharing: admitting the four-instruction scalar epilogue in
  `collectReturnTail` changes `check` from 25/3 to 23/3 static instructions/memory operands,
  but adds one executed unconditional jump to the recursive return and removes no executed
  restore. Nbody, Raytrace, ChaCha and SHA-256 counts and all five checksums are unchanged.
  This is a size tradeoff, not a speed-path improvement; the existing two-XMM-restore gate
  was retained. Together with the two nbody root schedules, this ends the focused static
  round after three consecutive attempts without a retained gain. Eight earlier batches
  remain integrated; the winner mechanisms have not yet converged. No further local
  rewrite is justified by the evidence: the remaining work needs register-pressure-aware
  vector plans, allocator strategy, or multiple unwind ranges.
- Final retained-code validation: 1205 C++ tests, 3532 native-suite tests in each of
  devmode and release (JIT and native), semantic positive/negative suites, scripts, the
  repository checks and all five inspected benchmark checksums pass. Restoring the failed
  prototypes restores the accepted instruction counts. No new timing campaign was run.
- Next: represent unwind ranges and parent links in `MachineCode`, emit them from the final physical instruction stream, and publish all ranges in native `.pdata` and the JIT function table. Then move only saves for registers first defined below the guard, with a proof for each path to a restore. Test both arms, nested calls and exceptional unwinding before and after the delayed saves in native and JIT output; compare no-hit and hit paths against MSVC.
- Complete when: the short path skips unused saves and restores without adding spill traffic to the hit path, and unwind and ABI checks pass; otherwise keep the current eager save plan.

### compiler.optimization.016 — General value-web normalization still extends live ranges too far

- Recorded: 2026-08-27 07:57
- Updated: 2026-09-30 18:31 — Rechecked scalar-double web splitting with the current interval allocator.
- Intent: give independent def-use webs separate virtual registers so LICM, value numbering
  and memory forwarding can distinguish computations that lowering gave the same name.
  Live phi joins and destructive updates must retain a common name. Dead phi cycles must not
  glue otherwise independent values together.
- Existing boundary: the unroller already renames independent temporaries in straight-line
  copies, but leaves carried values and bodies with internal labels unchanged. A flattened
  nested loop can therefore still contain independent values sharing a register.
- Rejected with the former hull allocator: the union-find prototype hoisted the deblock
  modulo chain, but grew `interpolateLuma` from 1583 to 1684 instructions and 314 to 398 frame
  references. No prototype from that experiment remains in the repository.
- Current experiment: a scalar-double union-find reconstruction over SSA values, with live
  phi and read-modify-write unions, still worsens unrelated floating code under interval
  splitting. Raytrace `intersect` grows from 205 to 211 instructions, 44 to 48 memory operands
  and 22 to 26 frame references; `trace` grows from 172 to 176 instructions and 56 to 58 memory
  operands. ChaCha, SHA-256 and binarytrees are unchanged. The broad rule was discarded.
- A narrower experiment splits only a reused register whose old value was stored and whose
  memory location is subsequently read. This leaves raytrace unchanged and enables nbody's
  cross-group velocity forwarding; see compiler.optimization.104. It does not establish a
  general normalization policy for arbitrary arithmetic temporaries.
- Next: attribute the extra floating interference and improve residency before expanding
  eligibility beyond a concrete store-to-load forwarding opportunity. Recheck the deblock
  consumer and raytrace alongside any broader rule; do not infer a win from renaming alone.
- Complete when: independent webs expose the intended hoisting and forwarding without
  worsening the affected hot paths through additional transfers or spill traffic.
- Related: compiler.optimization.015, compiler.optimization.104.

### compiler.optimization.102 — Retain one floating zero across unrolled arms

- Recorded: 2026-09-29 15:48
- Updated: 2026-09-29 16:02 — Reject branched-body renaming without zero reuse.
- Area: compiler/backend, value numbering and register allocation
- Evidence: the accepted raytrace winner is C++/MSVC. Its unrolled four-sphere `intersect` clears
  XMM5 once and compares each discriminant against that retained zero. Swag's corresponding
  205-instruction function clears XMM9 immediately before each of the four comparisons, adding
  three executed zeroing instructions to this path. Both implementations fully unroll the sphere
  loop, so loop rotation is not the missing mechanism.
- A scratch source copy named the zero explicitly before the loop; Release `intersect` remained
  205 instructions with four clears. A scratch value-numbering trial admitted `ClearReg` on virtual
  floating registers to share dominating definitions, with a C++ dominance test. It also left
  `intersect` at 205 instructions with four clears, and left `trace` and `main` at 172 and 136.
  The trial was reverted because it made no generated-code improvement; no runtime timing was
  taken. The full unroller renames private temporaries only when its body has no internal labels;
  `intersect` has conditional branches and `continue`, so the copies reuse the original virtual
  zero register. Value numbering requires the earlier result still held in its register, which
  each copy has overwritten before the next clear.
- A second scratch trial renamed private virtual values in a branched unrolled body only when
  each had one definition dominating all in-body uses and no outside reader. On its own it made
  `intersect` 209 instructions, up four, with all four clears intact. Combining it with the
  `ClearReg` value-numbering change also produced 209 instructions and four clears. The wider
  renaming perturbed XMM allocation and inserted extra copies; no executed path improved. Both
  trial edits were reverted without timing or broad correctness tests.
- Next: inspect a control-flow-aware way to split a private zero definition across cloned arms. A candidate should
  retain a single zero only where that saves executed clears without adding copies, spills, or
  saved registers. Compare an unrelated unrolled floating loop and a case with intervening calls
  before changing general value numbering or allocation.
- Complete when the repeated clears disappear with no new spill traffic in `intersect`, an
  unrelated case improves under the same rule, and native/JIT behavior remains correct.

### compiler.optimization.083 — Retain the probe mask without increasing spills

- Recorded: 2026-09-26 12:46
- Updated: 2026-09-29 15:37 — Inspect csvagg's executed hash and digit loops.
- Area: compiler/backend, LICM and register allocation
- Evidence: LDC retains wordfreq's `ByteMap.mask` in a callee-saved register across `memcmp`, while Swag reads `[m+mask]` during each collision step. Running LICM before instruction combine and allowing every invariant structure-field load across a read-only call moved that read out of the loop, but `mapProbe` grew from 81 to 98 instructions. The frame grew from `0x28` to `0x98`, the length and mask values spilled and reloaded, and an extra return tail appeared. The broad trial was reverted. A retained mask is only a gain if allocation keeps the loop's other live values resident too; one fewer memory operand in the collision step is insufficient evidence on its own. No timing was used.
- Repeating the early-LICM schedule after `mapProbe` was inlined into wordfreq's two token-finalization loops did not retain the mask: the resulting `main` still reads `[m+mask]` three times, stays at 451 instructions, and `qsort` grows from 132 to 133. The checksum remains 130489. This schedule trial was reverted without using timing.
- With the subsequent caller-test threading, wordfreq `main` was 443 instructions. Its first inlined probe still read `[rbx+0xC8]` for the initial hash mask and again for each collision step; LDC held that mask in `r10` across `memcmp`, saving and restoring it around the call. The Swag collision step retained the extra memory operand, while the checksum remained 130489. This was a code comparison, not a new LICM trial.
- Post-allocation loop rotation now recognizes the exit label after any run of adjacent labels following the back edge. It duplicates the `used[idx]` comparison at the collision tail and removes the unconditional jump: the first wordfreq collision path falls from seven to six runtime instructions, with three memory operands still versus LDC's two. The two inlined probes add two compares and two labels in total, so `main` rises from 443 to 447 static Micro instructions. The entry comparison remains on the cold entry path, and neither allocation nor spills change. All seven task checksums pass with `--validate-micro`; the other six selected function counts are unchanged. A C++ regression covers adjacent exit aliases and an intervening instruction. This closes .091; the mask load remains this entry's gap. No timing sample informed the decision.
- The accepted campaign `20260928-051818` named C++/clang-cl as wordfreq's fastest other runtime; the newer `20260929-105508` campaign names it again. Its inlined probe uses `and esi, 3FFFh` at collision, followed by the `used` and length tests: six instructions and two memory operands. A scratch-only trial marked `mapInit` inline; it exposed the constant `0x3FFF` to Swag, but enlarged `main` from 447 to 516 Micro instructions and reintroduced stack reloads and a back-edge jump in the collision loop. The checksum was 130489; the trial was rejected on static code quality, without timing.
- A post-allocation rule now moves a folded bitwise memory operand into an already saved, idle persistent register. It replaces the same address's straight-line entry read with a load and register operation, then rewrites every matching use in the loop. Eligibility requires a stable base, no loop memory writes, only direct calls annotated `ReadOnly`, and a register that is dead from the entry read through the loop. In wordfreq's first inlined probe, `r15` carries the mask across `memcmp`: the hot collision path remains six instructions and falls from three memory operands to two, matching the winner's counts. The entry still reads the mask once; it gains one encoded instruction but no memory access, while the frame and spill traffic stay unchanged. Thus `main` rises from 447 to 448 static Micro instructions. The final-token probe is unchanged because its entry read uses a different base expression. All seven task checksums pass under `--validate-micro`, and the other six selected function counts are unchanged. C++ tests cover an unrelated OR/XOR loop, a writable call, a memory write, a changing base, no prior read, a live scratch register, and no saved register. This is static evidence, not a measured runtime gain.
- Csvagg's newly accepted winner is Zig, which encodes the 64-slot probe mask as an immediate.
  A scratch-only `#[Swag.Inline]` on `mapInit` also exposes `0x3F` to Swag, but enlarges the
  Release `main` from 1,003 to 1,015 Micro instructions. The collision path gains register
  copies, two frame reloads, and unconditional jumps after key-length mismatch; it loses the
  conditional back edge that the preceding rotation established. This repeats the earlier
  wordfreq failure: exposing one constant by inlining the whole allocator-heavy initializer
  worsens the hot loop. The trial was rejected on static code quality without timing.
- A scratch-only post-RA refinement crossed the allocator spill stores at `[rsp+0x838]` and
  `[rsp+0x840]` before csvagg's probe loop, identified `rbx` as the local base despite a
  temporary `rcx = rsp` and the return-tail `pop rbx`, and kept the mask in the already saved
  `r15`. The collision step fell from three to two memory operations, but the entry mask
  operation grew from one instruction to two. The benchmark's eight region names hash to
  distinct slots modulo 64 (`21, 36, 16, 32, 12, 31, 14, 5`), so its collision step never
  executes; every lookup pays the extra entry instruction with no collision saving. The
  csvagg checksum remained 24828641 and the six other task checksums passed. The refinement
  was rejected on this executed-path evidence without a timing sample; no compiler rule was
  retained from the trial.
- The Release hash loop already reads four key bytes per iteration through the partial indexed-read
  unroller. Manually grouping four reads in a scratch source copy preserves checksum 24828641 but
  grows `main` from 1,003 to 1,007 Micro instructions, adding four address calculations before
  the grouped loop. This does not close a hot-path gap. The quantity and integer-price scans
  already reuse the delimiter-tested byte in the digit calculation. Their dynamic starting index,
  delimiter branch, and accumulator updates do not fit the current indexed-read unroller's
  zero-based, branch-free body; Zig's extra four-byte grouping applies to the two-digit fractional
  scan and needs its own setup and scalar tail. No compiler edit was retained from these probes.
- Next: compare wordfreq's complete probe paths and measure its retained mask at a clean paired
  campaign milestone. For csvagg, compare the successful `memcmp` and occupied-slot update with
  Zig's executed path; focus on register and frame traffic rather than its absent collisions.
- Complete when: a focused rule retains the mask without increasing spill traffic and improves paired wordfreq runs, or measurements show that retaining it is not profitable and this lead is retired.

### compiler.optimization.095 — Keep loop values off the stack on the common branch

- Recorded: 2026-09-28 14:04
- Updated: 2026-09-28 15:18 — Move the index spill store to the cold branch and remove the loop-latch store.
- Area: compiler/backend, path-sensitive spill placement
- Evidence: In wordfreq's character scan, the alphabetic path reaches a join where `r12` still holds the index, while token processing may reuse `r12`. The interval allocator had put the reload from `[rsp+0x210]` at that join, so every alphabetic character read the index from the stack. A post-allocation rule now moves the reload to the join's fallthrough edge only when every direct jump into the join can trace the same register value back to a matching frame store or reload without an intervening register definition, memory write, or call. It rejects a cyclic proof through the reload being moved. The common path loses one memory read; `main` grows from 448 to 450 static Micro instructions because subsequent branch layout changes, with no new instruction on that path. The checksum remains 130489; the other six benchmark checksums and selected function counts are unchanged. C++ (1,154), native Release (3,483), and JIT Release (1,500) tests pass. No timing sample was taken for this edit.
- A second post-allocation rule now moves a private spill store to the cold branch that dominates its sole read. It checks every explicit access to the eight-byte slot, rejects overlapping or indexed accesses, proves that the register still equals the slot on every incoming path, and tracks balanced stack-pointer adjustments along paths to the read. It removes later writes only when the new store lies on every route to the read. It applies only when at least one redundant write is removed: wordfreq's header and latch stores become one cold-entry store. The common alphabetic path now avoids the header store, join reload, and latch store, while `main` has 448 static Micro instructions and checksum 130489. A wider version moved a store in Leven without removing another write and raised its `main` from 474 to 478 instructions; the narrower rule restores 474 and checksum 67441. The other five benchmark checksums and selected function counts are unchanged. C++ (1,155), native Release (3,483), and JIT Release (1,500) tests pass with the final rule, as do all seven benchmark checksums. No timing sample was taken for this edit.
- The bound reload is placed the same way: once on the cold edge before the join and once after loop exit.
- Next: obtain a clean paired measurement at a campaign milestone.
- Complete when: the common character path has no index or bound spill traffic without adding costs to the token-processing path or changing JIT/native behavior; otherwise retain only the proven reload placement.

### compiler.optimization.092 — Reuse one relocation base for indexed constant arrays

- Recorded: 2026-09-28 09:14
- Updated: 2026-09-28 10:42 — Separate address materialization from the AVX memory-fold tradeoff.
- Area: compiler/backend, constant-address relocation and indexed loads
- Evidence: In the latest accepted full campaign (`20260928-051818`), raytrace's fastest other runtime is C++/MSVC (9.601 ms versus Swag's 10.742 ms; ratio 1.119). Its `trace` function materializes one image base with `lea rdi, [__ImageBase]` and reads eight distinct constant arrays through indexed memory operands. Swag's Release Micro for the same function uses eight `LoadRegPtrReloc` instructions followed by eight indexed loads, four for `SRAD`/`SCX`/`SCY`/`SCZ` and four for `SR`/`SG`/`SB`/`SRE`: 16 instructions for those reads versus MSVC's nine. This is an instruction and address-dependency gap, not a timing claim about an edit.
- A post-allocation rewrite that keeps the first array pointer and adds source-address differences to later loads is invalid for native artifacts: `NativeRDataCollector` emits only reachable allocations and may compact the gaps between them. JIT constants are resolved from shard and offset at patch time. Each indexed consumer therefore needs a relocation relative to a reusable segment or image base, or an equivalent layout contract that survives both backends. The existing emitter binds only RIP-relative scalar accesses, not indexed displacements.
- The native linker already understands `IMAGE_REL_AMD64_ADDR32NB` as an image-relative `Rva32` relocation, but code emission has no base-relative indexed relocation form, and the internal linker does not expose `__ImageBase` as a code symbol. The JIT's 2 GiB proximity arena can host code and constant shards together; its exhaustion fallback needs an explicit range or copy strategy for any base-relative displacement. In `trace`, the transient pointer register is clobbered by the intervening `intersect` call, so reusing that register alone yields at most two four-array groups. One base across both groups requires an allocation and callee-save decision.
- Folding a scalar indexed load into each floating operation is not an independent instruction saving here. Swag's load plus AVX three-register `fsub`/`fmul` is two encoded instructions; MSVC's copy plus memory-form SSE operation is also two in the corresponding `SCX`/`SCY`/`SCZ` and colour paths. The existing post-RA fold requires the destination to hold the left operand because the memory-form SSE instruction overwrites it. Adding a copy to force that fold would leave the instruction count unchanged and add a copy dependency.
- A separate check of `trace`'s missing `refl > 0` branch found no correctness defect: all four benchmark reflectivities are positive. A scratch function with a variable float retained both tests and produced `0,1,0` for negative, positive, and depth-limited inputs; changing one reflectivity to a negative value in an external source copy restored the floating compare in `trace`.
- Next: design and validate a relocation-aware indexed displacement against one reusable base in JIT and native output. Compare eight-array code with MSVC; include unrelated arrays in different allocations and shards, a library artifact, and a negative case whose address cannot share the base. Account for register lifetime across the intervening call and JIT arena exhaustion before selecting the base.
- Complete when: indexed reads of separate immutable arrays reuse one base without relying on source allocation spacing, pass JIT/native relocation checks, and close the eight-materialization gap without extra spills.

### compiler.optimization.093 — Keep unsigned 64-bit float conversion branchless in hot loops

- Recorded: 2026-09-28 09:31
- Area: compiler/codegen, integer-to-float conversion
- Evidence: The latest accepted campaign names C++/MSVC as csvagg's fastest other runtime (17.340 ms versus Swag's 18.304 ms; ratio 1.056). MSVC lowers each `u64` to `f64` price conversion with a signed conversion on the common lower half and a shift/or/double fallback for values with the high bit set. Swag instead uses a branchless packed low/high-32-bit conversion with two vector constants. Both have five instructions on the common path, but the operations and register pressure differ.
- A scratch compiler change used MSVC's general signed-fast-path formula. The 15 native boundary cases and a new JIT boundary case passed; 200,000 pseudo-random values and neighborhoods of powers of two agreed with the existing conversion. Csvagg's checksum stayed 24828641; all six other task checksums and selected function sizes were unchanged. The complete native Release suite passed 3,483 tests, JIT Release passed 1,501, and scripts passed.
- The emitted csvagg `main` grew from 993 to 1,022 Micro instructions. Its XMM saves fell from five to three and the saved area from `0x50` to `0x30`, but the timed row loop still had 13 frame operands and gained eight static jumps (34 to 42). Each common conversion still executed five instructions, now including a conditional and an unconditional jump. The two saves are paid once; the extra branches run for every row. This is a concrete hot-loop code-quality loss, so the trial and its JIT-only test were reverted without timing.
- Next: find a range proof that a conversion input stays below `2^63`, or a branchless lowering that uses fewer operations and less XMM pressure than the current packed conversion. Compare both sides of the range and an unrelated cast before revisiting the lowering.
- Complete when: a general rule improves the complete hot conversion path without extra branches or spills, and preserves full-range nearest-even results in native and JIT output; otherwise retain the current branchless algorithm.

### compiler.optimization.074 — Eliminate the caller's redundant used-slot test after an inlined probe

- Recorded: 2026-09-25 23:43
- Updated: 2026-09-28 00:30 — Thread the inlined probe's proven empty and occupied return paths.
- Area: compiler/backend, post-allocation branch threading and private-frame load elimination
- Evidence: In both wordfreq token-finalization paths, the inlined probe returns an index, then the caller loads the `used` pointer from its private frame, tests the indexed byte, branches if occupied, and loads the same pointer into the same physical register again on the empty fallthrough before storing. A guarded post-allocation rule removes that second load only when the base is the compiler-identified private stack base, the intervening operations are one read-only indexed compare and conditional jump, and both pointer loads have identical width and address. Wordfreq's `main` falls from 456 to 454 Micro instructions. Csvagg's `main` remains at 1,001; neither hash/collision loop changes. Both programs pass `--validate-micro` with checksums 130489 and 24828641. A C++ regression covers a private frame, a nonprivate base, and a different reload address. All 1,128 C++, 3,480 native, and 1,500 JIT tests pass. No elapsed-time sample informed the decision.
- Before branch threading, the loop-guided wrapper rule inlined both `mapProbe` call sites in wordfreq `main`, which grew from 327 to 451 optimized Micro instructions. Both paths still tested the `used[idx]` byte after the inlined probe's empty-slot exit; the probe could also return an occupied matching key after `memcmp`, so deleting the second test required a proof over the predecessor paths. The checksum was 130489. The other six benchmark tasks kept their optimized function counts and checksums. No timing sample informed that change.
- The post-allocation loop-layout pass now proves the indexed byte's zero/nonzero state backward along every incoming edge of the two adjacent return labels. It stops at a memory write, an address-register definition, an unannotated call, an unsupported edge, or a cycle; direct `ReadOnly` calls preserve the fact. It also keeps a label when an indirect jump targets it, since that jump cannot be retargeted here. Proven direct incoming jumps go straight to the caller's empty or occupied arm, and the repeated compare and branch disappear. Both wordfreq token-finalization paths make this change: `main` falls from 451 to 443 instructions, and an occupied key found by `memcmp` now branches directly to the value increment. LDC's winning `main` also follows its successful `memcmp` with a collision branch and a direct value increment, without a second `used` comparison. Csvagg's corresponding row path falls from 996 to 993 instructions; Odin's winner similarly goes straight from successful `memcmp` to its occupied update. The collision loop has no extra hot-path instruction. Checksums remain 130489 and 24828641 with `--validate-micro`; the other five tasks retain their selected function counts and checksums. A C++ regression covers both branch directions, a writable call, an intervening memory write, an index change, a different cell, and an indirect incoming jump. All 1,149 C++, 3,483 native Release, and 1,500 JIT Release tests pass. No timing sample informed the change.
- Next: recheck a full accepted benchmark campaign when the shared machine stays quiet.
- Complete when: broad validation and a clean full campaign confirm the generated-code gain without a runtime regression; retire the entry if no further path gap remains.

### compiler.optimization.089 — Mixed scalar calls slow down with six independent argument lanes

- Recorded: 2026-09-27 08:13
- Updated: 2026-09-27 21:13 — Retained the mixed-call measurement gate after changing float lanes
- Area: compiler/backend, Swag calling convention and register allocation
- Evidence: with the independent six-integer/six-float Swag argument banks, a release
  executable making 20 million no-inline calls with alternating six `u64` and six `f64`
  parameters takes about 61–64 ms after warmup, versus 34–36 ms with the prior
  positional convention on this machine. Both return the same value. Six-integer calls
  improve from roughly 37–41 ms to 31–33 ms over 40 million calls; six-float calls stay
  near 59–62 ms. These are process-wall microbenchmarks, not application measurements.
  With the same twelve-parameter signature but an integer-only body, the candidate
  improves to roughly 22–25 ms from 26–30 ms; with a floating-only body, it takes
  56–60 ms against 26–30 ms. Full-width XMM copies, pruning unused XMM saves,
  making XMM6/XMM7 volatile, and reducing Swag's float bank to three registers
  did not close the mixed-case gap in local experiments. The last result suggests
  that register count alone does not explain the slow floating body.
- The post-RA Micro dump for the floating-only body has a 17-instruction leaf
  callee under the old ABI, with three floating adds reading stack operands.
  The candidate has 25 instructions after dead-code elimination: five register
  floating adds plus a prologue and epilogue that save XMM6 and XMM7. Its first
  floating register copy is removed after the save plan is made. A temporary
  late save-pruning experiment still measured around 58 ms, so the saved-register
  instructions alone do not explain the entire gap.
- An experimental mapping that kept six independent integer lanes but assigned
  floating arguments by their position in the full signature measured roughly
  37–42 ms on the mixed sum, close to the old 39–42 ms in the same run. It gives
  up independent floating lanes for mixed signatures, so it was not selected as
  the new Swag convention.
- The preceding candidate used the already persistent XMM6–XMM11 as floating argument
  lanes. Pre-prologue dead-definition elimination avoids saving unused persistent
  registers; a property-based loop pass hoists invariant persistent-argument copies.
  In five alternating call-matrix pairs, six-integer calls are about 10% faster,
  six-float calls about 16% faster, and alternating six/eight mixed calls remain
  about 3% slower than the preceding ABI. These backend passes apply by convention
  properties and remain useful even if the Swag ABI changes again.
- The transient XMM0–XMM5 experiment removes two per-pixel row reloads from raytrace's
  inner loop and reduces its `main` and `trace` from 155/201 to 136/173 optimized Micro
  instructions. All seven benchmark checksums remain unchanged; the six other tasks
  retain their instruction counts. C++ (1,147), native Release
  and DevMode (3,483 each), JIT Release (1,500), and workspace Release pass with the
  cache identity advanced to build 1173. The old persistent-argument copy hoist became
  unreachable and was removed. No elapsed-time sample informed the choice.
- Next: compare the mixed-call signatures and the seven tasks in a paired campaign with
  the new float bank; isolate any signature or task that regresses before closing this entry.
- Complete when: repeated paired runs put the mixed calls at parity or better and
  the six-integer and six-float gains remain.

### compiler.optimization.085 — Measure short-key comparison cost against LDC

- Recorded: 2026-09-26 13:10
- Updated: 2026-09-27 17:44 — Retain the unmeasured short-key performance comparison after the completed runtime change.
- Area: generated runtime code, wordfreq byte-map keys and comparators
- Evidence: wordfreq and LDC both call `memcmp` for variable-length keys of 3–8 bytes. Swag's runtime fallback scanned the sub-eight-byte tail one byte per loop iteration; a matching three-byte key therefore repeated two byte loads, a comparison, an increment, and a loop branch three times. The fallback now compares four-, two-, and one-byte chunks without reading past `size`, and uses the lowest set bit of a nonzero XOR (or the first clear SIMD equality bit) to return the exact first unsigned byte difference. The whole `memcmp` body grows from 96 to 115 optimized Micro instructions, but the frequently used short equal-key path has no byte loop; a three-byte key needs one two-byte comparison and one byte comparison. `mapProbe`, `qsort`, and wordfreq main remain 81/72/328 instructions, and the checksum remains 130489 with `--validate-micro`. The new native test checks every mismatch position in sizes 1–64 with unaligned inputs and both operand orders. Its five focused tests pass in Release and DevMode; the 3,481-test native Release, 1,500-test JIT Release, and focused core memory suites pass. No elapsed-time sample informed the decision.
- Next: compare the issued short-key path against the C runtime used by LDC and recheck the wordfreq ratio only after further static gains, since the larger generic fallback alone does not establish a benchmark speedup.
- Complete when: final short-key code and repeated paired wordfreq measurements establish competitive cost, or isolate a reproducible remaining gap whose implementation can be specified here.

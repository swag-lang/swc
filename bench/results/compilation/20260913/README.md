# Static compilation-cost reductions, 2026-09-13

Latest validated compiler: **build 550**. Each batch is functionally validated before
integration into master. The load-admission waiver applies to this session; performance
measurements remain deferred until the final campaign.

| Batch | Compiler build | C++ tests | Native tests (`devmode` / `release`) | Details |
| --- | --- | --- | --- | --- |
| 1, including current-master integration | 525 | 685 passed | 3,131 / 3,131 passed | Sections below |
| 2 | 527 | 696 passed | 3,131 / 3,131 passed | [Repeated scans and layouts](batch2.md) |
| 3 | 529 | 700 passed | 3,131 / 3,131 passed | [Lazy analyses and legalization](batch3.md) |
| 4 | 531 | 701 passed | 3,131 / 3,131 passed | [Conditional scratch-register scan](batch4.md) |
| 5 | 532 | 705 passed | 3,131 / 3,131 passed | [Frame analysis and live instruction scans](batch5.md) |
| 6 | 533 | 712 passed | 3,131 / 3,131 passed | [Phi worklists and ordered stack depths](batch6.md) |
| 7 | 534 | 716 passed | 3,131 / 3,131 passed | [Allocation, aliases and relocations](batch7.md) |
| 8 | 535 | 719 passed | 3,131 / 3,131 passed | [Legalization and SSA restores](batch8.md) |
| 9 | 536 | 724 passed | 3,131 / 3,131 passed | [CFG, forwarding and register scans](batch9.md) |
| 10 | 537 | 730 passed | 3,131 / 3,131 passed | [SSA fast paths and register discovery](batch10.md) |
| 11 | 538 | 733 passed | 3,131 / 3,131 passed | [Register claims, restores and float reads](batch11.md) |
| 12 | 541 | 738 passed | 3,131 / 3,131 passed | [SSA inference and relocation collectors](batch12.md) |
| 13 | 542 | 743 passed | 3,131 / 3,131 passed | [Occurrence maps, sinking and saved registers](batch13.md) |
| 14 | 544 | 751 passed | 3,131 / 3,131 passed | [SSA consumers and conditional analyses](batch14.md) |
| 15 | 545 | 754 passed | 3,131 / 3,131 passed | [Inferred constants and restore bookkeeping](batch15.md) |
| 16 | 546 | 757 passed | 3,131 / 3,131 passed | [Copies, branches, epilogues and relocations](batch16.md) |
| 17 | 547 | 759 passed | 3,131 / 3,131 passed | [Integer results and SLP permutation roots](batch17.md) |
| 18 | 548 | 760 passed | 3,131 / 3,131 passed | [Extensions, tuple keys and coalescing setup](batch18.md) |
| 19 | 549 | 763 passed | 3,131 / 3,131 passed | [Predecessors, returns and early load rejection](batch19.md) |
| 20 | 550 | 763 passed | 3,131 / 3,131 passed | [Early header and multiplier rejection](batch20.md) |

## Worker count and deferred comparison

Benchmark compilation is not capped at six workers by default. `--cores` in
[`bench/compile.py`](../../../compile.py) and `--swc-cores` in
[`bench/driver.py`](../../../driver.py) default to zero. The
[workload builder](../../../toolchains.py) then omits `--num-cores`, and compiler
processes use [`winproc.run`](../../../winproc.py) with its default `pin=False`.
The driver's six-performance-core affinity applies to executing timed benchmark
programs. The six-worker limits in this report apply only to validation.

The pending campaign must compare Release compiler binaries built from recorded
baseline and final revisions, using identical workload sources and build settings.
Keep their paths and hashes with the results, force rebuilds, alternate candidate
and baseline order, and retain per-round wall time, CPU time and memory samples.
Report paired ratios and the observed spread; the September 12 figures remain
historical and do not quantify the additional static changes recorded here.

The existing [compile-only comparison script](../20260912/compare.py) compiles the
seven native benchmark inputs and core without running generated benchmark programs.
After preparing fresh `bin/swc.baseline.exe` and `bin/swc.candidate.exe`, these are
commands for that future campaign, not commands run in this continuation:

```text
python bench/results/compilation/20260912/compare.py --label final-native-release --cfg release --cores 0 --reps 7
python bench/results/compilation/20260912/compare.py --label final-core-devmode --cfg devmode --tasks core --cores 0 --reps 7
```

Run them when the shared CPU is quiet. The script retains its own admission checks;
this session's validation waiver does not turn noisy timing samples into useful evidence.
Its JSON output is under `.tmp/compile-perf`; archive that output with the exact revisions
and common source identity before drawing conclusions. No benchmark or timing campaign
was launched for these static batches.

The remaining sections document the first batch and its integration.

Continuation in `perf/micro-compile-time`, based on `f23cfb69a`, compiler build 524.
The user requested further static improvements without waiting for timing measurements.
The [September 12 report](../20260912/README.md) retains the earlier measurements;
those numbers do not measure this additional change.

## Removed work and preserved invariants

| Change | Work removed | Why the result is preserved |
| --- | --- | --- |
| LICM and induction-variable analysis collect instruction use/def directly | Full SSA construction, including phis and SSA dominators, on every internal round | These passes only queried instruction-local use/def; they retain their own CFG/dominator analysis and invalidate shared SSA after mutation. |
| Induction-variable use counts are shared across natural loops | Repeated whole-function use counting and map construction for each loop | The pass stops after changing a loop; every loop examined before that sees the same instruction stream. |
| LICM collects loop definitions alongside memory effects | A second full instruction scan per loop | Both calculations read the same instruction-local effects before planning mutations. |
| LICM caches in-loop use counts across acceptance retries | Repeated counting and map allocation when a rejected web restarts acceptance | Acceptance only changes the hoist plan and banned set; instruction uses remain unchanged until plans are applied. |
| LICM records the loop body in listing order | Scanning the whole function during each acceptance retry, exit scan, and use check | The filtered list contains exactly the same body instructions in the same order; checks of entire spans between definitions still examine the original listing. |
| Post-RA convergence prunes unchanged suffixes | Re-running passes after they already observed the final IR of a sweep | Any earlier mutation immediately reactivates the entire suffix. The second sweep remains complete because forwarding policy changes after the first. Iteration limits stay unchanged. |
| SSA predecessor and dominator-child lists append directly | Linear duplicate searches, quadratic for large joins or dominator fan-out | Each source block's successor list is already unique; each block is attached to its single immediate dominator once. |
| Dominance-frontier construction stamps visited paths per join | Duplicate frontier searches and repeated ancestor walks from converging predecessors | Once two paths meet, the remaining dominator path has already received that join. Join order and frontier order are preserved. |
| Disconnected-component discovery keeps a forward cursor | Repeated scans from block zero for unreachable components | Visited blocks never become unvisited; root discovery order is unchanged. |
| Single-block SSA skips general dominator and phi setup | DFS, fixed-point workspaces, definition-block collection, phi worklists | The only block dominates itself; no two-predecessor join exists inside this block representation. |
| Trivial SSA use queries return before preparing traversal scratch | Visit stamps and traversal-stack operations for empty use lists or a first direct instruction use | These cases directly answer the existing boolean or capped-count query. |
| The rename position replaces an unread instruction-reference field | Enlarging every SSA instruction record and writing the unused reference | The removed field had no readers; instruction references remain in the slot/order mapping and SSA value records. |
| Dominance queries use dominator-tree DFS intervals | Walking the ancestor chain for every dominance test | A node dominates exactly the nodes in its subtree interval. The conversion reuses existing construction buffers; unreachable nodes retain invalid markers. |
| DCE shares one SSA snapshot across removal waves | Rebuilding CFG, dominators, phis, and SSA for every level of a dead chain | Erasing a dead definition cannot change a surviving use's reaching value. Per-wave usage propagates backwards from surviving instruction consumers through phis, including cycles. Erasure order and live flag checks remain unchanged. |
| Constant folding checks viable operands before flag scans | Scanning suffixes for operations whose values are unknown; scanning for constant-memory loads without any constant relocation | These early exits apply only when the original fold could not succeed. |
| Post-RA DCE uses shared physical-register liveness masks | Repeated linear register-set searches and duplicate liveness implementation | The backward fixed point and ABI exit roots are the same; unrepresentable registers remain conservatively live. |
| Post-RA loop hoisting counts definitions in two masks during classification | A body scan for each reload candidate | The masks distinguish one defining instruction from several, ignoring duplicate definitions inside one instruction. |
| Post-RA loop rotation indexes incoming jumps | A whole-function jump scan for every header | Counts and source ordinals are read from the same unmodified listing; changes remain deferred. |
| Loop unrolling indexes first and last incoming jump sources | Two scans of all jumps per candidate | The source extremes establish a unique incoming jump and whether all incoming jumps to an internal label lie inside the body. The index is rebuilt after mutation. |
| SLP builds SSA only for a viable plan and scans fresh registers only before materialization | Full SSA work for unpackable blocks and register scans when no plan is emitted | Every mutation still follows snapshot construction; later blocks use that same snapshot and monotonically allocated registers. |
| Vector-loop promotion collects stack-pointer definitions during its initial scan | Repeated instruction use/def collection in every loop body | Membership checks cover exactly the same stack-pointer definitions before any mutation. |

The reaching-definition index and sink-to-use changes from September 12 remain.
No optimization rule or iteration budget is weakened. No new timing sample or
benchmark execution is part of this continuation.

## Validation

Added 21 C++ tests in this continuation cover dead chains, phi cycles, flag consumers,
constant folding, post-RA liveness and loop recognition, suffix reactivation, unrolling
with external entries, lazy SLP analysis across blocks, stack-pointer changes, and a
three-predecessor SSA join. The dominance oracle now checks every possible CFG root,
including unreachable nodes. Existing LICM tests and the native optimizer cases cover
instruction effects, aliasing, induction products, and sums inside branches.

Three agents implemented separate pass families and then cross-reviewed other families.
The user waived machine-load admission for this session before validation; compiler builds
and tests retained their six-worker caps. No timing comparison was run.

| Validation | Result | Evidence |
| --- | --- | --- |
| DevMode compiler build 524, MSBuild `/m:6` and `SwcCompileJobs=6` | Passed | [Build log](build-devmode.log) |
| C++ suite, build 524 DevMode compiler | 685 passed, including all 21 added tests | [C++ log](cpp.log) |
| Native suite, build 524 DevMode compiler, program configuration `devmode` | 3,131 passed; native executable ran successfully | [Native devmode log](native-devmode.log) |
| Native suite, build 524 DevMode compiler, program configuration `release` | 3,131 passed; native executable ran successfully | [Native release log](native-release.log) |

Commands, run from the separate worktree:

```text
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm cpp --num-cores 6
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm native -bc devmode --num-cores 6
bin/swc.dm.exe --num-cores 6 tools/unittests.swgs dm native -bc release --num-cores 6
```

Each command exited with code 0. The PowerShell logs retain its `NativeCommandError`
wrapper around compiler progress written to stderr; this wrapper is not a failed test.
`git diff --check` passes. New C++ test files are registered in `swc.vcxproj`.
No misplaced `.output` directory was found under the test sources; only the canonical
`bin/unittests/.output` remains. The [repository backlog validator](repository.log) passed with exit code 0.
No Release compiler rebuild or further timing campaign was needed for this continuation.
The previous build 523 measurements and microcode comparison remain historical evidence
in the September 12 report; they do not measure build 524.

## Integration with master

Build 525 combines the validated static changes with master `516cc0531`.
Only the version and backlog index needed conflict resolution; the micro-pass changes
were unchanged. The DevMode build, all 685 C++ tests, and all 3,131 native tests in each
of `devmode` and `release` passed again on the combined sources, with six workers.
Evidence: [build](integration-build.log), [C++](integration-cpp.log),
[native devmode](integration-native-devmode.log), [native release](integration-native-release.log).
The [repository backlog validator](integration-repository.log) also passed. These are functional checks, not performance measurements.

The [second batch](batch2.md) records the next static reductions and build 527 validation.

The [third batch](batch3.md) records lazy dominance, phi setup, and legalization probes (build 529).

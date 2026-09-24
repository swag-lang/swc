# Compilation speed campaign, 2026-09-24

This campaign ran in the detached `swc-speed` worktree with the Release compiler and
at most six Swag workers. The compiler was rebuilt from source and the full Release
test sequence passed before optimization. Every later batch used a focused compiler
test boundary. Build 1093 passed a second full Release rebuild and test sequence.
Integrated build 1095 passed the full Release sequence again after further backend
merges. Build 1096 passed an incremental Release build and 3,478 focused native tests.
Build 1097 passed an incremental Release build, 3,478 native tests and 1,500 JIT tests.

## Baseline and targets

`bench/compile.py --swc bin/swc.exe --swc-cores 6 --admit --reps 5 --only
core_rebuild,core_noop,core_touch,hello_build` measured build 1078. The medians
below are from the same five-run baseline series. `core_rebuild` compiles all 360
files in `std/core`; `hello_build` includes linking.

| Workload | Baseline wall | Baseline CPU | Peak working set | Target |
| --- | ---: | ---: | ---: | ---: |
| Core rebuild | 2,921.5 ms | 13,015.6 ms | 566.0 MiB | <1,000 ms |
| Core warm no-op | 46.2 ms | 46.9 ms | 10.2 MiB | <100 ms guardrail |
| Core one-file touch | 2,406.8 ms | 11,203.1 ms | 525.8 MiB | exploratory |
| Hello source to executable | 151.3 ms | 562.5 ms | 54.4 MiB | <50 ms |

## Final four-workload comparison

Five alternating rounds compared integrated build 1093 (A) with the preserved
build 1078 (B), using the current source inputs for both. These results include
independent generated-code changes merged to `master` during the campaign and
therefore cannot attribute an end-to-end difference to the retained speed batches.

| Workload | A wall median | B wall median | A CPU median | B CPU median | A/B peak working set |
| --- | ---: | ---: | ---: | ---: | ---: |
| Core rebuild | 3,633.9 ms | 3,531.6 ms | 15,734.4 ms | 15,515.6 ms | 578.1 / 545.4 MiB |
| Core warm no-op | 53.4 ms | 55.5 ms | 31.2 ms | 31.2 ms | 10.2 / 10.3 MiB |
| Core one-file touch | 2,397.1 ms | 2,557.5 ms | 10,687.5 ms | 11,359.4 ms | 565.0 / 527.1 MiB |
| Hello source to executable | 182.1 ms | 153.7 ms | 593.8 ms | 578.1 ms | 56.5 / 52.9 MiB |

The core rebuild series includes a 25.3-second A run and a 29.3-second B run;
the warm no-op B also had a 771 ms outlier. The direct comparison is too noisy
to claim a compiler-speed improvement. It also observes more peak working set
for A in the compile workloads. That memory difference requires further attribution
across the intermediate compilers before assigning it to a retained batch.

A second five-pair comparison used preserved build 1083, after the SSA batches,
against build 1078. Peak working set was 575.6 versus 560.4 MiB for core and
55.8 versus 54.6 MiB for hello. The paired B/A working-set ratios were 0.973
and 0.977: the retained SSA capacities appear to account for a small portion
of the aggregate memory increase. This series also contained a 30.4-second
baseline core outlier and a 2.2-second baseline hello outlier. Later compiler
snapshots include independently merged backend optimizations, so the remaining
aggregate difference cannot be assigned to one batch from these measurements.

## Retained changes

| Compiler area | Retained work | Validation and timing interpretation |
| --- | --- | --- |
| SSA value propagation | Share the value, flag, canonicalization and erase buffers between three micro passes, then retain SSA state, phi, renaming and analysis capacities between functions. | Native and JIT suites passed after each batch. Seven-pair core results were mixed and below the measurement floor. The changes remove repeated vector allocation without a reliable end-to-end percentage. |
| Value numbering | Retain hash-table buckets and vector capacities per compiler worker while clearing keys at each function. | 3,477 native and 1,500 JIT tests passed. Seven-pair core B/A wall 0.979, CPU 1.000; no claimed speedup or material memory change. |
| Sanitizer propagation | Share one refined state across successors when they receive identical facts; move an owned state into the first reached block. | Native and safety suites passed. Both one- and six-worker A/B runs contained large, inconsistent outliers in both binaries. The retained change removes state-map copies; no percentage is claimed. |
| Branch reachability | Reuse reachability vectors, use the CFG label table instead of building a hash map, and record address-taken label targets during CFG construction instead of scanning the function again. | 3,478 native tests passed after each refinement. The five-pair direct comparison of the vector and label-lookup batch gave core B/A wall 1.046 and CPU 1.062; a later comparison including an independent LICM merge was neutral. The removed scan and hash table are structural savings; there is no isolated speedup claim for the final refinement. |
| Register allocation label lookup | Reuse the CFG's label-to-instruction table for guarded-call and loop-region analysis instead of constructing two hash tables and scanning labels again. | Release build, 3,478 native and 1,500 JIT tests passed. Seven alternating pairs gave core B/A wall 0.988 and CPU 0.987, below the measurement floor. No speedup or regression is claimed. |
| Register allocation buffers | Retain nine fully overwritten analysis vectors on the per-worker pass object across functions: loop depth, loop labels, benefit scores and reservation counts. | Release build, 3,478 native and 1,500 JIT tests passed. Seven alternating core pairs gave B/A wall 1.027 and CPU 1.021, with peak working set ratio 1.010. This is a small favorable signal near the measurement floor, not a firm percentage claim. |
| Native read-only zero data | Detect a zero-filled allocation without relocations in its source span, then emit `.rbss` directly without copying bytes into a discarded `.rdata` section. | Release build and 3,478 native tests passed. The first seven-pair core comparison was disrupted by an 11.5-second candidate run; a quieter five-pair repeat gave B/A wall 1.042 and CPU 1.050, with peak working set 1.010. |
| Dead code elimination scratch | Keep the used-value bitmap and worklist on the per-worker pass object; overwrite both on each run. | Release build, 3,478 native and 1,500 JIT tests passed. The first seven pairs were disrupted by 4–5-second candidate outliers. A quiet five-pair core repeat gave B/A wall 1.012, CPU 0.991 and peak working set 1.004: below the measurement floor. |

All A/B runs alternated candidate A and preserved compiler B. `B/A > 1` favors
the candidate. Some runs expanded from about 3 seconds to 20–29 seconds on
`core_rebuild`, and `hello_build` sometimes rose from about 0.2 to 2 seconds in
both versions. These outliers preclude an aggregate percentage claim. They also
make a ratio of separate medians misleading; paired wall and process CPU must
agree before treating a result as a measured win.

The optimization target remains open. The structural changes perform the same
required compiler phases; none changes cache invalidation, skips linking, or
changes the benchmark inputs.

## Afternoon continuation

Build 1098 reused the CFG label table in register allocation. Seven alternating
pairs compared it with preserved build 1097 on the same source inputs. Core rebuild
median wall time was 1,838.5 ms for 1098 versus 1,844.9 ms for 1097; median process
CPU was 8,328.1 versus 8,250.0 ms. Hello build median wall time was 115.1 versus
112.5 ms. The first core pair was 4,883 versus 2,803 ms while both compilers warmed,
so neither a speedup nor a regression is established. Peak working set was also
indistinguishable in paired results. The removed allocations and scans justify
retaining this small structural change.

Build 1099 retained capacity for nine register-allocation analysis vectors. Seven
alternating pairs against preserved build 1098 gave core rebuild median wall
1,806.0 versus 1,844.1 ms and process CPU 8,218.8 versus 8,093.8 ms; paired
ratios, which account for the alternating order, favored 1099 by 1.027 wall and
1.021 CPU. Six of seven core wall pairs favored 1099. The paired peak working-set
ratio was 1.010 in favor of 1099, so no memory regression was observed. Hello
build wall was neutral (paired ratio 1.003); its CPU samples were too coarse and
variable to establish a change. The core signal is near the measurement floor,
so the retained conclusion is the removal of repeated vector allocations.

An attempted worker-local `InstructionCombine` context was rejected. Retaining
its action queue and hash tables had no repeatable core speed benefit in seven
pairs and raised peak working set. Releasing the action queue after each run
still regressed core rebuild in five alternating pairs: baseline/candidate
ratios were 0.959 wall and 0.955 CPU, while the peak working-set ratio was
0.984. The context reset and retained hash-table buckets cost more than this
allocation reuse saved, so the source was restored to build 1099.

Build 1102 moved the `.rbss` decision ahead of the section copy. The first
seven-pair comparison was not suitable for a percentage claim: a candidate
core run took 11.5 seconds and 40.7 CPU seconds while the surrounding runs
were near 3 seconds and 15 CPU seconds. A quieter five-pair core-only repeat
favored build 1102 over preserved build 1099 by 1.042 wall and 1.050 CPU in
paired baseline/candidate ratios. Four of five wall pairs favored 1102. Peak
working-set ratio was 1.010 in its favor. The direct removal of a discarded
byte copy is retained; the clean repeat is encouraging but the two series do
not establish a stable aggregate percentage.

The subsequent integration with an independent instruction-combine batch used
cache identity 1103. Its incremental Release build passed, followed by 3,478
native and 1,500 JIT tests. The timing above belongs to the isolated build
1102, so it does not attribute the independent batch's effect to this change.

Build 1104 reused the dead-code pass's two temporary vectors. Seven alternating
core and hello pairs encountered candidate core runs above 4 and 5 seconds
while the surrounding runs were near 2–3 seconds. A subsequent five-pair core
series on a quieter machine gave baseline/candidate ratios 1.012 wall and
0.991 CPU, with peak working set 1.004. This is neutral within the measurement
floor; the retained benefit is avoiding two vector allocations per pass run.

## Final validation

The Release solution rebuild from source succeeded at build 1093 with MSBuild `/m:6`
and `SwcCompileJobs=6`. The full Release sequence also exited zero at integrated
build 1095. Its compiler suites passed 1,500 JIT and 3,478 native tests. The
safety suite passed 138 tests; seven dynamic cases remained the same expected
non-passing cases seen at baseline. The standard workspace passed 2,390 tests,
applications passed 550, and the language reference passed 479. Script runs and
the 32 example and four application smokes also completed. Build 1096 then passed
3,478 native tests after the loop-unroll merge. Build 1097 incorporates the later
loop-rotation merge and passed an incremental Release build, 3,478 native tests and
1,500 JIT tests. The full Release sequence was not repeated for that final merge.

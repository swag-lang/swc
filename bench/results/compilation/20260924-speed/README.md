# Compilation speed campaign, 2026-09-24

This campaign ran in the detached `swc-speed` worktree with the Release compiler and
at most six Swag workers. The compiler was rebuilt from source and the full Release
test sequence passed before optimization. Every later batch used a focused compiler
test boundary. Build 1093 passed a second full Release rebuild and test sequence.
Integrated build 1095 passed the full Release sequence again after further backend
merges. Build 1096 passed an incremental Release build and 3,478 focused native tests.
Build 1097 passed an incremental Release build, 3,478 native tests and 1,500 JIT tests.
Build 1108 passed a later full Release rebuild and test milestone.
Builds 1125 and 1127 passed two further full Release milestones.

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

Five alternating rounds compared final isolated build 1127 (A) with the
preserved build 1078 (B), using the same current source inputs and six workers.

| Workload | A wall median | B wall median | A CPU median | B CPU median | Peak working set A / B | Target |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Core rebuild | 2,284.7 ms | 2,805.0 ms | 10,671.9 ms | 13,265.6 ms | 585.8 / 560.9 MiB | <1,000 ms |
| Core warm no-op | 39.1 ms | 49.1 ms | 31.2 ms | 31.2 ms | 10.2 / 10.2 MiB | <100 ms |
| Core one-file touch | 1,871.7 ms | 1,957.6 ms | 8,812.5 ms | 9,437.5 ms | 548.7 / 535.0 MiB | exploratory |
| Hello source to executable | 143.6 ms | 128.0 ms | 515.6 ms | 437.5 ms | 57.6 / 55.9 MiB | <50 ms |

Paired B/A ratios were 1.238 wall and 1.213 CPU for core, 1.059 for both
wall and CPU after touching a file, and 0.964 wall and 0.955 CPU for hello.
The fifth round slowed both binaries, particularly the touched-file build.
Core and touch improved overall, while hello regressed and the final compiler
used more peak working set on every compilation workload. These differences
include independently merged generated-code changes, so none is assigned as a
percentage gain to the speed-only batches. The core and hello targets remain
unmet; the warm no-op guardrail passes.

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
| SSA reaching-value capacity | Keep each register's reaching-value buffer when a function has no tracked registers or fewer registers than its predecessor; clear only active buffers before renaming. | Release build, 3,478 native and 1,500 JIT tests passed. Seven core pairs gave B/A wall 0.999, CPU 0.989 and peak working set 1.011: no measured speedup or memory regression. |
| SSA restore allocation | Let the inline restore vector grow from actual saved definitions instead of reserving from the block's instruction count. | Release build, 3,478 native and 1,500 JIT tests passed. The first seven pairs included a 6.5-second candidate core outlier; a five-pair core repeat gave B/A wall 1.050, CPU 1.032 and peak working set 1.007. No stable aggregate percentage is claimed. |

All A/B runs alternated candidate A and preserved compiler B. `B/A > 1` favors
the candidate. Some runs expanded from about 3 seconds to 20–43 seconds on
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

Integrated build 1105 includes the concurrent instruction-combine change. Its
incremental Release build, 3,478 native tests and 1,500 JIT tests passed. The
DCE timing comparison above was made on isolated build 1104.

Build 1106 retained SSA reaching-value capacities across small and empty
functions. Seven alternating pairs against build 1105 gave core B/A 0.999 wall
and 0.989 CPU, and 1.011 for peak working set. Hello wall was neutral. The
change removes repeated inner-vector destruction and reconstruction; its
end-to-end timing remains below the measurement floor.

Build 1107 removed the eager reserve for each SSA rename block's restore list.
The first seven-pair comparison had a 6.5-second candidate core outlier and
gave B/A 1.000 wall and 0.962 CPU. A subsequent five-pair core repeat gave
B/A 1.050 wall, 1.032 CPU and 1.007 peak working set, though one candidate
run was again disrupted. The local vector already stores eight restore points
inline, so allocations now follow actual definitions rather than the block's
instruction count. The two series support retaining this simpler path without
claiming a stable end-to-end percentage.

## Release validation milestones

The Release solution rebuild from source succeeded at build 1093 with MSBuild `/m:6`
and `SwcCompileJobs=6`. The full Release sequence also exited zero at integrated
build 1095. Its compiler suites passed 1,500 JIT and 3,478 native tests. The
safety suite passed 138 tests; seven dynamic cases remained the same expected
non-passing cases seen at baseline. The standard workspace passed 2,390 tests,
applications passed 550, and the language reference passed 479. Script runs and
the 32 example and four application smokes also completed. Build 1096 then passed
3,478 native tests after the loop-unroll merge. Build 1097 incorporates the later
loop-rotation merge and passed an incremental Release build, 3,478 native tests and
1,500 JIT tests. The next full Release milestone was build 1108.

The afternoon milestone rebuilt integrated build 1108 from source in Release
(MSBuild `/t:Rebuild /m:6`, `SwcCompileJobs=6`) without warnings or errors.
`bin/swc.exe --num-cores 6 tools/tests.swgs --num-cores 6` exited zero:
1,500 JIT, 3,478 native, 138 safety passes with the same seven expected
non-passing dynamic cases, 2,390 standard-module, 550 application and 479
reference tests. Script runs, 32 example builds and four application smokes
also completed.

The independent vector-backend merge advanced the cache identity to build
1109. Its incremental Release build passed, followed by 3,478 native and
1,500 JIT tests. The earlier full-sequence result belongs to build 1108.

Build 1110 replaced SSA's per-function sweep over every retained instruction
slot with a cache epoch. The epoch changes before each new function, so the
existing use/def cache remains valid only within that function; wraparound
explicitly resets the epochs. This removes a walk proportional to the largest
function previously compiled on that worker. Its Release build, 3,478 native
and 1,500 JIT tests passed. The first seven-pair core rebuild comparison was
disrupted by a concurrent C++ build and gave baseline/candidate ratios 0.978
wall and 0.970 CPU. A quieter five-pair repeat gave 1.011 wall and 0.979 CPU,
with peak working set ratio 1.005. Wall and CPU do not agree on a gain; the
change is retained for its simpler per-function cost, with no percentage
speedup claim. WPR CPU sampling was attempted, but system profiling privileges
were unavailable on this host (0xc5585011); no fresh trace was recorded.

A subsequent experiment retained constant folding's relocation-address hash
table in the shared worker scratch instead of constructing it per pass run.
The isolated build 1111 passed 3,478 native and 1,500 JIT tests, but seven
alternating core rebuild pairs gave baseline/candidate ratios 0.964 wall and
0.955 CPU: both indicate a roughly 4% regression. The paired peak working-set
ratio was 0.999, though the candidate's highest sample was 600.9 MiB versus
585.1 MiB for the baseline. Hello build wall was neutral. The source was
restored to build 1110: retaining this hash table did not justify its cost.

Build 1111 reused the physical-register liveness analysis's worklist and
membership vector per worker. The two buffers are fully reset before each
fixed-point solve; the change removes two allocations per analysis invocation.
Its incremental Release build and the focused C++ compiler, 3,478 native and
1,500 JIT test suites passed. The first alternating core/hello series was
interrupted by an internal error in the unchanged build 1110 reference
compiler: `Core.HashTable.find` lost the bound function symbol for
`.tryFind(key)` during code generation. That reference executable had passed
thirteen core rebuilds in the same series; ten immediate isolated repetitions
also passed. This is tracked as compiler.core.057, separately from the
post-register-allocation scratch change. A subsequent five-pair core-only
comparison gave baseline/candidate ratios 0.961 wall, 0.995 CPU and 0.993
peak working set. Wall and CPU disagree on a material regression, and sample
times drifted during both series; no stable timing change is claimed. The
structural allocation reduction is retained. Visual Studio's CPU collector
was also attempted, but its service was not registered (0x80040154), so this
host still has no fresh CPU trace.

The subsequent merge with the independent native address-mode changes uses
cache identity 1113. Its incremental Release build and the focused C++
compiler, 3,478 native and 1,500 JIT test suites passed. The liveness timing
above belongs to the isolated build 1111 and does not include that merge.

One more independent global-arithmetic batch was merged with cache identity
1114. The incremental Release build and focused C++ compiler, 3,478 native and
1,500 JIT suites passed. No end-to-end timing claim is assigned to this
integrated binary.

Build 1115 shared the worker's graph-walk stack and byte marks between
physical liveness, natural-loop body collection and dominator traversal.
Each algorithm resets the buffers before reading them; no algorithm calls
another while those buffers are live. Its incremental Release build and
focused C++ compiler, 3,478 native and 1,500 JIT suites passed. Core A/B
series were unusable: separate concurrent builds coincided with 42.1 s and
38.2 s core outliers in the candidate and reference respectively, against
ordinary 2-4 s runs. A later direct pair took 3.31 s candidate and 3.39 s
reference. Three hello pairs gave reference/candidate wall 1.035 and CPU
0.769; CPU samples are coarse at this workload length. No repeatable speedup
or regression is established. The source retains the smaller shared scratch
and removes three temporary allocations across these sequential analyses.

The independent global bitwise and fixed-shift address-mode updates were
integrated as build 1117. Its incremental Release build and focused C++
compiler, 3,478 native and 1,500 JIT suites passed. Those updates are not
included in the isolated build 1115 timing observations.

Build 1118 records whether each reachable native constant allocation is all
zero while its source bytes are still available. The collector skips copying
those bytes into the already zero-initialized merged buffer, and the COFF
writer reuses that classification when selecting `.rbss`; relocations still
force initialized `.rdata`. This removes a copy for each zero allocation and
moves the byte scan from the writer to the collector. The prediction was less
native object-construction CPU and no meaningful peak-memory change. The incremental
Release build, 3,478 native and 1,500 JIT tests passed. A five-pair
core/hello comparison against build 1117 gave core reference/candidate ratios
0.975 wall and 0.937 CPU; a second five-pair core comparison gave 1.013 wall
and 1.078 CPU. The first candidate core invocation in each comparison was a
28-32 s, 109-120 s CPU outlier, whereas ordinary invocations of both binaries
were about 3-4 s and 13-16 s CPU. With opposing paired series there is no
repeatable end-to-end gain or regression. Core peak working set was 584.0 vs
578.8 MiB in the first series and 588.9 vs 580.6 MiB in the second (candidate
vs reference maxima). The simpler zero-allocation path is retained below the
measurement floor; no percentage speedup is claimed.

Build 1119 retains the dominator walk's child-cursor and postorder capacities
on each compiler worker. Its DFS stack is reused for reverse postorder after
the DFS empties it, eliminating three vector allocations per dominator-tree
construction. The prediction was lower backend CPU without a material memory
increase. The incremental Release build, 3,478 native and 1,500 JIT tests
passed. Five alternating core/hello pairs against build 1118 gave core
reference/candidate ratios 0.959 wall, 0.947 CPU, 1.004 peak working set; a
five-pair core repeat gave 1.127 wall, 1.080 CPU, 0.984 peak working set.
There was a 39.5 s core outlier in the candidate in the first series and a
36.5 s outlier in the reference in the second, each using over 130 s process
CPU. The series disagree and cannot support a speedup or regression claim;
the removed allocations are retained below the measurement floor.

Release `tools/unittests.swgs cpp` is a no-op by design: the linked C++ unit
tests exist only in DevMode. Earlier notes that the Release `cpp` selector
"passed" mean that selector exited successfully, not that C++ tests ran. The
reported native and JIT counts are executed tests.

The independent in-place rotation folding update was merged as build 1120.
Its incremental Release build, 3,478 native and 1,500 JIT tests passed. The
dominator-buffer timing above is from isolated build 1119, before this merge.

Twelve direct build-1120 core rebuilds using the same executable took 3.4-3.9 s
for the first eleven runs, then 10.9 s and 48.4 s process CPU on the twelfth.
The compiler's own module summary put 9.3 s in `core`, while `win32` and
`xinput` remained below 0.3 s each. This confirms that large core outliers
also occur without switching compiler binaries; the available Release summary
does not split the core module into finer stages.

Build 1121 retains seven SSA block-discovery and dominator-workspace vector
capacities across builds and functions on each compiler worker. The block
leader bitmap becomes the visited bitmap only after block discovery has
finished. Every buffer is overwritten before use. The prediction was fewer
allocator calls per SSA rebuild and no material peak-memory increase. The
incremental Release build, 3,478 native and 1,500 JIT tests passed. A first
five-pair comparison against build 1120 gave core reference/candidate 1.180
wall and CPU and hello 1.276 wall, 1.186 CPU. A seven-pair repeat gave core
1.001 wall and 0.986 CPU, hello 1.031 wall and 0.868 CPU; peak working set
was 583.6 versus 583.8 MiB for core and 57.5 MiB for both hello binaries
(candidate versus reference maxima). Both series contained 40-second core
outliers in the reference. The favorable first series did not reproduce, so
no end-to-end speedup is claimed. The allocation reduction is retained below
the measurement floor.

The independent indexed/unary memory-operand folding updates were integrated
as build 1123. Its incremental Release build, 3,478 native and 1,500 JIT
tests passed. The isolated build-1121 SSA timing above predates this merge.

Build 1124 defers allocation of the CFG label-to-instruction table until the
first valid label appears. Functions with no labels no longer reserve that
vector, while labeled functions retain the previous reserve estimate. The
prediction was one fewer allocation per unlabeled function, with negligible
peak-memory effect. The incremental Release build, 3,478 native and 1,500 JIT
tests passed. Five core/hello pairs against build 1123 gave core
reference/candidate ratios 0.934 wall and 0.921 CPU and hello 1.072 wall and
1.333 CPU; the series included a 39.9 s candidate core and a 3.0 s reference
hello outlier. A five-pair core repeat gave 0.972 wall and 1.056 CPU with
peak working set ratio 1.018; it included a 38.8 s reference core and an
8.3 s candidate core. Wall and CPU disagree across series. The removed
allocation is retained below the measurement floor, without a speedup claim.

The independent x64 encoder, emission and address-mode updates were integrated
as build 1125. Its incremental Release build, 3,478 native and 1,500 JIT
tests passed. The isolated build-1124 timing above predates this merge.

Build 1125 then passed a clean Release source rebuild and the full Release
`tools/tests.swgs` milestone: 1,500 JIT, 3,478 native, 2,390 standard-module,
550 application and 479 language-reference tests, plus the safety, script,
example and application-smoke boundaries. The safety suite's seven expected
dynamic nonpasses remained unchanged. This milestone predates the next
physical-liveness scratch experiment.

A subsequent experiment shared one thread-local physical-liveness result
between post-RA dead-code elimination, peephole and loop hoisting. Its
isolated build 1126 and the 3,478 native/1,500 JIT suites passed. Five
core/hello pairs against build 1125 gave core reference/candidate 1.004 wall
and 1.023 CPU, but hello 0.956 wall and 0.828 CPU. A seven-pair hello repeat
gave 0.963 wall and 1.000 CPU. The repeated roughly 4% hello wall regression
is not justified by the removed allocations, so the source was restored to
build 1125.

The final isolated compiler for this campaign is build 1127, including the
independent RIP-memory folding changes merged through that identity. A clean
Release source rebuild and the complete Release `tools/tests.swgs` sequence
passed: 1,500 JIT, 3,478 native, 2,390 standard-module, 550 application and
479 language-reference tests, plus safety, scripts, 32 example modules and
four application smokes. The seven expected dynamic safety nonpasses remained
unchanged. Later generated-code commits on `master` are separate from this
validated and measured compiler snapshot.

After the report was drafted, the independent RIP-memory changes through
build 1130 were integrated in the speed worktree. An incremental Release
build, 3,478 native and 1,500 JIT tests passed. The complete Release
sequence and four-workload table above remain the build-1127 results.

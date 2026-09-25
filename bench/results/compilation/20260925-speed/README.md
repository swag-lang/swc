# Compiler-speed session, 2026-09-25

Worktree: `C:/Perso/swag-lang/swc-speed`, branched from `fd24f96ca` (Release compiler
build 1142). The campaign used the Release compiler only, with six compiler workers.
The source tree is back at its starting commit: **no compiler optimization was
retained**. The attempted change and the measurements below are preserved so that
the same approach is not accepted on misleading evidence.

## Four edit-loop workloads

`bench/compile.py` already drives all four workloads through `swc.exe`, records wall
time, process CPU time, peak committed memory and peak working set, and uses the same
recipes as the full benchmark history. Five baseline runs gave:

| Workload | Median wall | Median CPU | Peak resident | Prompt target |
| --- | ---: | ---: | ---: | --- |
| Full `std/core` rebuild | 3,874.7 ms | 16,000.0 ms | 590.7 MiB | Under 1,000 ms |
| Warm `std/core` no-op | 64.8 ms | 31.2 ms | 10.3 MiB | Under 100 ms |
| One `std/core` source touched | 3,026.1 ms | 13,312.5 ms | 548.3 MiB | Diagnostic workload; no numeric target |
| Hello world through linking | 220.6 ms | 656.2 ms | 56.2 MiB | Under 50 ms |

The first round was disturbed: `core_touch` took 38.3 seconds and `hello_build`
2.84 seconds, whereas later rounds returned near 3 seconds and 0.21 seconds.
These medians are a starting observation, not a quiet-machine performance claim.
See [baseline samples](baseline-four-workloads.log).

## Profile and hypothesis

A separate Release build with a PDB was sampled externally on one `std/core`
rebuild. The sampler observed 284 stacks representing 14.453 seconds of worker CPU.
Inclusive attribution was 60.86% in `CodeGenJob::exec`, 53.41% in
`MicroPassManager::run`, 11.35% in `MicroSsaState::build`, 10.27% in
`MicroBranchSimplifyPass::run`, and 3.35% in
`MicroControlFlowGraph::build`. These inclusive percentages overlap and the
sampler perturbs execution. See [profile](core-profile.txt) and
[compiler output](core-profile-compiler.log).

A separate `std [gui]` profile first rebuilt its dependencies, so its 2,009
samples and 315.906 sampled worker CPU seconds describe the whole eight-module
workspace rather than GUI alone. Its Release-program build stopped at the
existing `compiler.core.058` dynamic type-test error in
`properties.input.swg:174`; the DevMode-program build passed. See the
[workspace profile](gui-devmode-profile.txt),
[build output](gui-devmode-profile-compiler.log), and
[Release failure](gui-release-profile-compiler.log).

With those dependencies warm, touching only `gui/module.swg` rebuilt just GUI.
The module took 9.451 seconds (10.173 seconds for the command). The sampler
observed 864 stacks and 48.344 sampled worker CPU seconds. Inclusive
attribution was 43.02% in `Sema::runCurrentVisit`, 40.76% in `CodeGenJob::exec`,
32.93% in `MicroPassManager::run`, 28.77% in `semaCallExprCommon`, 10.02% in
`appendConstantFunctionJitRoots`, and 8.34% in `MicroBranchSimplifyPass::run`.
The percentages overlap, and sampling perturbs the run. Unlike the workspace
profile, this trace isolates the GUI module. The touched file's original
timestamp was restored after the command. See the
[GUI-only profile](gui-only-profile.txt) and
[compiler output](gui-only-profile-compiler.log).

## Worker-count diagnostic

Five one-worker `core_rebuild` runs had an 11.633-second median wall time and
10.156-second median process CPU time. The six-worker series was interrupted
after three runs because machine load defeated admission for subsequent runs:
its first two builds took 3.672 and 3.472 seconds with 14.875 and 14.641
seconds of process CPU, then the third took 49.768 seconds and 165.172 seconds
of process CPU. These are separate series, not order-alternated pairs. They show
that six workers can reduce wall time while increasing CPU work on this source,
but do not establish a stable scaling factor or isolate why CPU work rises.
See the [one-worker log](core-one-worker.log) and
[interrupted six-worker log](core-six-worker.log).

The trial tracked control-flow changes since the most recent graph invalidation in
`MicroBranchSimplifyPass::run`. Previously, several boundaries invalidated the
graph whenever *any* earlier transform in the run had changed it. The prediction
was fewer redundant graph rebuilds on functions that change early, worth less than
1% of a full core build, with no memory increase or output change. The trial
temporarily moved `SWC_BUILD_NUM` to 1143 and built the Release compiler.

Focused Release-program validation passed: the native
`branch_simplification.swg` and `short_circuit_booleans.swg` files ran one test
each, and the randomly drawn JIT file `var_struct_local.swg` ran 12 tests. See
[branch test](candidate-native-branch.log),
[short-circuit test](candidate-native-short-circuit.log), and
[random JIT test](candidate-random-jit.log). No full candidate Release campaign
was run before the trial was discarded.

## Comparison and decision

Five alternated A/B rounds, with baseline A and candidate B, returned these median
paired B/A ratios:

| Workload | Wall | CPU | Peak resident |
| --- | ---: | ---: | ---: |
| `core_rebuild` | 1.249 | 1.234 | 1.005 |
| `core_noop` | 1.260 | 2.000 | 1.001 |
| `core_touch` | 0.808 | 0.872 | 1.011 |
| `hello_build` | 0.981 | 1.062 | 1.005 |

The ratios disagree across workloads, and individual builds moved from roughly
3 seconds to more than 40 seconds under background load. See the
[complete A/B log](candidate-four-workloads-ab.log). A follow-up core-only series
was interrupted after two pairs: candidate samples took 39.7 and 39.9 seconds,
but a later rebuild with the restored baseline compiler also took 49.5 seconds
during the full test campaign. Those two candidate samples therefore cannot
establish a candidate-specific regression. See the
[interrupted series](candidate-core-rebuild-quiet-ab.log) and
[restored baseline samples](restored-core-rebuild.log).

Two byte-identical copies of the restored baseline compiler were then compared,
one beside the worktree resources and one using external junctions to those same
resources. Five A/A pairs gave median B/A 1.000 wall and 1.044 CPU, with single
core rebuilds spanning 2.7 to 5.8 seconds. There is no stable path bias large
enough to explain the earlier extremes, but this control confirms that transient
load survives admission and alternating order. See [A/A control](identical-binaries-core-ab.log).

The trial was reverted because it did not establish a repeatable gain or a
regression-free structural saving. The original compiler was restored in the
worktree, and a three-run core control measured 4.03–4.63 seconds (4.35-second
median). There is no retained source or version change.

## Empty JIT relocation trial

The GUI-only profile put 10.02% of sampled worker CPU in
`appendConstantFunctionJitRoots`. This walks the emitted call graph for each
compile-time call. A second small trial returned one shared empty target list
when a function's lowered code had no relocations, before acquiring its target
cache lock or allocating a list. Such a function cannot contribute a constant
JIT target. The prediction was a gain of about 1% on GUI at best, with no
output or memory increase. The trial temporarily moved `SWC_BUILD_NUM` to
1143 and built the Release compiler. The focused Release-program JIT
`global_function_ptr.swg` test passed (one test). See the
[build log](jit-empty-candidate-build.log) and
[focused test](jit-empty-global-pointer.log).

Five alternated baseline/candidate pairs on the normal benchmark recipes gave
`core_rebuild` median B/A 0.982 wall, 0.996 CPU and 1.007 peak resident;
`hello_build` gave 1.011 wall, 0.927 CPU and 1.010 peak resident. Wall and CPU
do not establish the predicted benefit across these workloads. See the
[core and hello comparison](jit-empty-core-hello-ab.log).

To isolate GUI, two external copies of `bin/std` had their dependencies warmed
separately; each timed command touched only its copy of `gui/module.swg`, built
the 319-file GUI module, then restored the source timestamp. Five alternated
pairs gave median B/A 0.756 wall, 0.782 CPU and 1.033 peak resident. The
individual wall ratios span 0.147 to 1.519. In one pair, the baseline took
111.5 seconds and 485.8 seconds of CPU, versus the candidate's 16.4 and 70.9;
the change cannot plausibly account for that difference given the profiled
upper bound. See the [GUI comparison](jit-empty-gui-ab.log).

An A/A control then ran the byte-identical baseline compiler against those
same two workspaces. It was stopped after two pairs as machine load continued
to distort the result: its first B run took 128.8 seconds and 505.9 seconds of
CPU against A's 14.5 and 67.1; the second pair was 8.6 versus 8.9 seconds
with close CPU time. The large GUI ratios therefore cannot be attributed to
the candidate. See the [partial A/A control](identical-binaries-gui-aa.log).
The second trial and its version bump were reverted, and the byte-identical
baseline compiler was restored. No random test or full Release campaign was
run for the discarded candidate.

## Release validation

The baseline Release compiler was rebuilt from source before the trial. Its first
complete Release test command returned code 1 after printing successful results
through application smoke, without a final diagnostic in its log. The focused
application smoke returned code 0 immediately afterward. A second complete
Release test command on the restored baseline compiler returned code 0: 1,500
JIT, 3,478 native, 2,390 standard-module, 550 application and 479 reference
tests passed, followed by scripts and all 32 example and four application
smokes. The unexplained first exit remains an observation, not a green run.
See the [first log](baseline-release-tests.log) and
[passing rerun](baseline-release-tests-rerun.log).

Next work should focus on a larger measured code-generation cost. Any retry of
conditional graph invalidation needs a per-transform proof that no unreported
operand or control-flow mutation can occur between its synchronization points.

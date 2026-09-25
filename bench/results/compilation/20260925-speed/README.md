# Compiler-speed session, 2026-09-25

Worktree: `C:/Perso/swag-lang/swc-speed`, detached from `fd24f96ca` (Release compiler
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

# Micro backend compilation time, 2026-09-12

Further static improvements are recorded in the [September 13 follow-up](../20260913/README.md).

Worktree: `C:/Perso/swag-lang/swc-compile-perf`, branch `perf/micro-compile-time`,
starting commit `f23cfb69a`. Baseline compiler: 0.1.521. Final candidate: 0.1.523.
The initial loaded series and microcode captures use 0.1.522; 0.1.523 has the same
backend implementation and adds three sink-to-use C++ tests and a cache-identity bump.

This experiment only compiles the benchmark inputs. It does not run the benchmark
campaign or execute any generated benchmark program, and does not update bench history.

## Historical signal and worker count

The archived campaigns on September 6 and September 12 show `core_rebuild` (devmode)
increasing from 2,915 to 3,429 ms (+17.7%), with CPU time increasing from 28,422 to
33,547 ms (+18.0%). The seven native release compilations increased by 5.5% to
33.3%. Those campaigns use different compiler and library revisions, and the latter
was recorded from a dirty checkout; they establish the symptom, not its attribution
to one backend change. See [September 6](../../20260906-143159.json) and
[September 12](../../20260912-183805.json).

Both archives record `swc_cores: 0`. Their `pin_cores: 6` setting applies to executing
benchmark programs: `bench/driver.py` passes `pin=True` to `run_once`, but compilation
uses `winproc.run` with its default `pin=False`. Neither the normal benchmark builds
nor this final comparison cap compilation at six workers.

## Implementation

`MicroSsaState` used to copy every active register into every block's entry state.
Each reaching-definition query then scanned backward through the current block and,
if necessary, searched that entry snapshot. These costs recur after mutating passes
invalidate SSA, and grow with both block length and the number of active registers.

The candidate records each register's value changes along the dominator-tree rename
walk. Each instruction records its position before its writes; scope restores and
phi definitions update the index before the next instruction. A binary search over
one register's changes answers arbitrary reaching-definition queries, including
queries at instructions that do not read that register. This removes whole-state
entry snapshots and repeated backward scans. Phi placement, SSA value identities,
use lists, pass ordering, and the invalidation contract remain the same.

`SinkToUse` now caches instruction-local use/def information directly. Its movement
checks only need those register effects; constructing full SSA on each of its up to
four rounds computed dominators, phis, and reaching definitions it never queried.

No optimization pass, iteration limit, vectorization policy, or inlining policy was
disabled or reduced. Compiler identity is incremented for cache separation.

## Measurement protocol

- Both binaries are built in this worktree with MSVC Release, `/MP6`, and `/m:6`.
  This limits construction of the C++ compiler, not the measured Swag compilations.
- Measured comparison compilations use the compiler's default worker count: **22 workers**
  on this machine, without an affinity restriction. The user explicitly requested
  unrestricted benchmark compilation. Earlier six-worker diagnostics are not part
  of the final comparison.
- Native inputs use the seven recipes from `bench/toolchains.py` and program
  configuration `release`. Core uses the existing `core_rebuild` command with
  `--rebuild`, in both `devmode` and `release` configurations.
- Every command recompiles its inputs. Binaries alternate A/B, B/A, A/B by round.
  Reported ratios are medians of paired candidate/baseline ratios, not ratios of
  independent minima. Process wall time, CPU time, peak resident memory, job commit,
  and estimated background CPU are recorded by the existing `bench/winproc.py`.
- Each compilation passes the repository memory/CPU admission check. An initial
  stricter 20% CPU ceiling admitted only one pair before sustained background load;
  that incomplete series is retained as `quiet-prefix.json`. A 35% ceiling also
  admitted only a partial series, retained as `loaded-prefix-35.json`. Both are
  excluded from the complete-series aggregates. The loaded measurements use the repository's
  normal 65% ceiling and are explicitly measurements under background load.
  Background work can start after admission; the raw samples retain that observed load.

## Measurements under background load (0.1.522)

Three complete alternating pairs per row. Times are independent medians in milliseconds;
deltas are medians of paired candidate/baseline ratios. Negative deltas indicate less
time or memory. These noisy observations do not establish repeatable latency gains.

| Input / configuration | Wall baseline | Wall candidate | Paired wall | Paired CPU | Paired resident memory |
| --- | ---: | ---: | ---: | ---: | ---: |
| wordfreq / release | 260.0 | 147.3 | -37.6% | -21.2% | -2.8% |
| csvagg / release | 184.1 | 230.5 | +25.2% | +1.3% | -2.7% |
| sha256 / release | 264.3 | 223.2 | -11.3% | -25.3% | -1.5% |
| dijkstra / release | 327.0 | 206.5 | -23.1% | -34.0% | -0.8% |
| raytrace / release | 301.7 | 229.2 | -3.8% | -11.5% | -4.6% |
| leven / release | 315.0 | 211.0 | -33.0% | +4.8% | -3.4% |
| chacha / release | 247.4 | 284.0 | -12.3% | -16.7% | -4.5% |
| core / release | 2658.1 | 2581.6 | +2.0% | -6.9% | -0.9% |
| core / devmode | 5464.6 | 4671.8 | -14.5% | +0.5% | +8.3% |

Core release illustrates the uncertainty: its first pair took 2.66 / 2.47 seconds,
while its third took 4.52 / 6.56 seconds as background CPU rose to 44% / 58%.
Core devmode has almost unchanged paired CPU time and higher candidate resident
memory in every pair (about +1.6% to +8.6%). This is a memory tradeoff to remeasure;
removing snapshots does not by itself prove lower peak memory, since the new index
also retains per-register histories and adds an instruction position.

Both optimizations are retained as requested. Their individual contributions have
not been isolated; these comparisons measure the combined change.

Raw complete series: [release](ssa-index-release-all-workers-loaded.json),
[devmode](ssa-index-devmode-all-workers-loaded.json).

## Final attempt with stricter admission (0.1.523)

After the final builds and C++ tests completed, the machine briefly had less
background activity. A new three-round release comparison used a 20% admission
ceiling and the final 0.1.523 candidate. It completed one round across all eight
inputs and a second pair for wordfreq and csvagg (20 compilations total).
Sustained load then returned, repeatedly blocking admission. Observed background
CPU during admitted compilations still ranged from 3.4% to 41.7%.

This attempt was stopped and retained as
[release-quieter-final-partial.json](release-quieter-final-partial.json). It is
excluded from the complete-series aggregates above. A short quiet admission
window was insufficient to obtain a stable full comparison; no reliable global
wall-time improvement is claimed. The implementation and reproduction tools remain
available for a complete repeat on a quiet machine.

## Validation

- Both compiler configurations build successfully.
- Final DevMode compiler: 664 C++ tests pass, including three new SSA tests covering
  queries before redefinitions and at non-uses, rebuild after deletion, sibling
  dominator scopes, loop phis, and unreachable roots, plus three sink-to-use tests
  covering movement to the consumer and barriers for base redefinition and memory writes.
- Release compiler 0.1.522, program `release`: 3,131 native tests pass.
- DevMode compiler 0.1.522, program `devmode`: 3,131 native tests pass.
- The final microcode of 70 benchmark-owned functions across all seven programs
  matches after relocation normalization. The capture uses temporary source copies
  with `#global #[Swag.PrintMicro("pre-emit")]`; no benchmark algorithm is changed.
- `git diff --check` passes. The repository/backlog check reports one pre-existing
  inconsistency: `backlog/README.md:39` lists `cpu.simd.md` at 2026-09-12 22:10,
  while that domain's latest stamp is 2026-09-12 18:05. Both files match the starting
  commit and were not changed here. See [repository.log](repository.log).

The comparison retains instruction order, slot references, opcodes, registers,
widths, immediates, branch targets, and symbolic call/constant previews. It normalizes
process addresses and assigns consistent names to global/constant relocations,
preserving their identity across the captured functions. Every function's captured
instruction count is checked against the compiler's count. This checks microcode
equivalence; it does not claim byte-identical PE images or measure runtime speed.
Per-function hashes are in [microcode-comparison.json](microcode-comparison.json).

## Reproduction

Build the starting commit and the candidate with the same Release settings, keeping
the former as `bin/swc.baseline.exe` and the latter as `bin/swc.candidate.exe` beside
the same runtime sources. The measurement commands are:

```powershell
python bench/results/compilation/20260912/compare.py --reps 3 --max-cpu 65 --label release-all-workers-loaded
python bench/results/compilation/20260912/compare.py --tasks core --cfg devmode --reps 3 --max-cpu 65 --label devmode-all-workers-loaded
python bench/results/compilation/20260912/compare.py --reps 3 --max-cpu 20 --label release-quieter-final
python bench/results/compilation/20260912/capture.py
```

The capture uses six workers because it is a correctness check, not a timing sample.
This worktree retains `bin/swc.baseline.exe` (0.1.521), `bin/swc.ssa-index.exe`
(the measured 0.1.522 intermediate), and `bin/swc.candidate.exe` (final 0.1.523).
Each timing JSON records its exact compiler SHA-256 hashes and command lines.
The full benchmark campaign, benchmark execution, other language toolchains,
documentation generation, and the full repository test campaign were not run.

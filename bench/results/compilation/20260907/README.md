# Standard-module compilation campaign, 2026-09-07

Worktree: `C:/Perso/swag-lang/swc-speed-20260907`, branch
`codex/compile-speed-20260907`, starting commit `8d3f0498b` (compiler 0.1.390).
The campaign concentrates on `gui`, `pixel`, and `ogl`, with `core` as a control.
The retained compiler changes are committed as `c44de46b4` (compiler 0.1.393).

## Module measurements

The first completed final series is explicitly **under background load**, with three
alternated pairs, six pinned performance cores, and `devmode` programs. Absolute
times are per-binary medians; ratios are medians of the paired B/A ratios, so they
need not equal the quotient of the two time columns.

| Module | Baseline wall | Candidate wall | Paired wall B/A | CPU B/A | Resident peak B/A | Committed peak B/A |
|---|---:|---:|---:|---:|---:|---:|
| GUI | 12.901 s | 16.643 s | 1.189 | 1.442 | 1.030 | 1.023 |
| Pixel | 9.739 s | 7.440 s | 0.764 | 0.756 | 0.991 | 0.998 |
| OGL | 3.955 s | 1.224 s | 0.306 | 0.447 | 0.999 | 0.993 |
| Core | 4.704 s | 3.980 s | 0.846 | 0.843 | 1.025 | 1.021 |

[Raw samples](final-modules-pinned-loaded.json) include every admission and CPU
deltas across every timed process; [module-summary.json](module-summary.json) keeps
the aggregates. OGL and Pixel improve in all three wall/CPU pairs. GUI is slower
in all three pairs, but background CPU is also higher for every candidate sample:
38.4/45.8%, 22.0/55.0%, and 9.3/33.9% for A/B respectively. The second candidate
GUI run took 89.278 seconds and 358.984 CPU seconds. It is retained in the record.
This series cannot establish an overall GUI gain or separate a compiler regression
from the changed load. No outlier is silently discarded and no overall memory
improvement is claimed for GUI or Core.

An additional [GUI control](gui-fixed-dependencies.json) warms the dependency graph
once with the baseline, then alternates five A/B pairs without rebuilding dependencies.
All 69 dependency artifacts are hashed and remain byte-identical after every sample.
It uses the same six-core affinity and a stricter 35% admission ceiling, although
background activity can still rise after admission.

| Fixed-dependency GUI | Baseline median | Candidate median | Median paired B/A |
|---|---:|---:|---:|
| Wall time | 13.066 s | 12.304 s | 0.942 |
| Process CPU | 44.781 s | 44.063 s | 0.886 |
| Resident peak | 1,215.7 MiB | 1,235.5 MiB | 1.037 |
| Committed peak | 1,307.9 MiB | 1,338.7 MiB | 1.048 |

The roughly 6% paired wall reduction is compatible with the removed GUI hotspot,
but background CPU remains unequal (A/B by pair: 34.7/26.0%, 39.3/19.4%, 21.3/19.2%,
35.7/33.7%, 24.5/23.6%). It is a loaded observation, not a precise promised speedup.
The resident and committed peaks increase in this control and need explanation;
faster phases may change overlap, but that cause has not been established.
`repo.tooling.008` retains this unresolved memory question. No overall GUI improvement
without a memory cost is claimed.

## Prompt 4 targets at the noon cutoff

The existing compile-loop workloads completed two full A/B then B/A pairs under
load. The requested third round was interrupted after its first Core rebuild to
close the campaign at noon; that unpaired sample is preserved in the raw file but
excluded from these aggregates. See [raw results](legacy-ab.json),
[console log](legacy-ab.log), and [aggregates](legacy-summary.json).

| Workload | Baseline median | Candidate median | Paired wall B/A | Target |
|---|---:|---:|---:|---|
| Full Core rebuild | 3.655 s | 4.256 s | 1.229 | <1.000 s; unmet |
| Warm Core no-op | 76.4 ms | 56.7 ms | 0.754 | <100 ms; observed in both binaries |
| One Core file touched | 3.496 s | 3.696 s | 1.112 | <300 ms; unmet |
| Hello to linked executable | 167.1 ms | 182.3 ms | 1.135 | <50 ms; unmet |
| Standard-library documentation | 50.791 s | 127.077 s | 2.505 | Halve; unmet |
| Repository source formatting | 6.621 s | 5.341 s | 0.806 | Halve; unmet |

`doc_std` is the existing standard-library workload, not the complete `tools/web.swgs`
website pipeline; the latter was not measured. Formatting uses the existing private
source/configuration mirror. The no-op and formatting CPU ratios are 1.000 and
0.997: their wall differences do not establish a compiler-work reduction.
Documentation is substantially slower in these two candidate samples (CPU ratio
2.197), with the slow region moving between dependency compilation and HTML
generation. This wrapper did not record system CPU during those samples, so load
cannot be used to dismiss the regression. `repo.tooling.008` records the required
follow-up. These results do not establish an overall prompt-4 win.

## Measurement procedure

- Release C++ compiler, optimized with LTCG, with a PDB for external sampling.
- Swag program configuration `devmode`, six compiler workers. Program `release`
  is separately covered by validation and the generated-program benchmarks.
- A private mirror of the 1,467 tracked `bin/std` files isolates measurements from
  the test tool's workspace cleanup. Module contents are unchanged.
- A complete dependency build warms the selected compiler before timed builds.
  Touching only the selected module's `module.swg` measures its rebuild with warm
  dependencies. The original source timestamp is restored after each command.
- Pairs alternate A/B then B/A. Report the median of paired B/A ratios, alongside
  wall time, process CPU time, resident peak, and job committed peak.
- Every compilation is admitted by the repository's CPU and memory check. The first
  comparisons additionally waited for CPU below 15%. The final quiet series could
  not start: its first measured admission was 23%. The explicitly loaded final
  series uses the normal 65% admission ceiling and records background CPU during
  every sample. Neither admission prevents activity from starting during a sample.
- An additional diagnostic series uses the existing benchmark's six-performance-core
  affinity mask (`0x55401`). Keep that series separate from ordinary unpinned builds.

The initial unpinned series has very large within-binary variation. Another compiler
campaign was active early in the session. Later, the OLED screensaver alone consumed
7.05 CPU seconds in a five-second observation. These data must not be presented as
precise end-to-end gains without the repeated controls.

## Profile evidence and hypotheses

External profiles are in [profiles](profiles). [sample.cpp](sample.cpp) is the
standalone Windows sampler; no instrumentation was added to the compiler. It samples
the launched process's active threads, weights stacks by their recent CPU time, and
resolves the Release PDB. Sampling perturbs execution, and recent CPU time can be
attributed to a thread that has just gone idle. Percentages are approximate inclusive
attribution, not independent stage timings to add together.

| Workload | Baseline attribution | Hypothesis |
|---|---:|---|
| GUI alone | COFF constant-allocation writer 7.57% | Scanning every relocation for each allocation repeats module-wide work; binary-search its sorted range. |
| OGL alone | Public export overload collection 43.93% | Collecting and sorting every symbol for each exported name repeats unrelated work; query the name's existing homonym chain. |
| Pixel alone | Natural-loop discovery 6.02%; dominance call line 5.78% | Forward edges cause pointless walks to the dominator root; use existing reverse-postorder positions to stop negative queries early. |
| Pixel alone | SSA build 22.15%; rename 11.63%; entry snapshot line 5.82% | SSA rebuilds repeatedly destroy block scratch storage; evaluate retaining storage while reconstructing all analysis. Snapshot copying remains a separate cost. |

Variants were frozen beside the worktree compiler: `swc.baseline.exe` (390),
`swc.rdata1.exe` (391), `swc.overloads.exe` (392), `swc.dominance.exe` (393),
and `swc.ssa-storage.exe` (394). Their hashes belong to each raw measurement record.
Executables and PDBs remain ignored local artifacts.

## Retained implementation

- `NativeObjFileWriterCoff.cpp` finds each constant allocation's first relocation
  with `lower_bound` and stops at the allocation end. The collector already emits
  allocations and their relocations in offset order; an assertion now protects that
  contract. The native-artifact test checks adjacent allocation objects, an interior
  addend, and a referenced string. This removes the repeated module-wide scan without
  changing bytes, relocation order, or ownership.
- `Symbol.Function.cpp` uses the existing locked name lookup and homonym chain when
  collecting public overloads. It no longer enumerates and sorts an entire namespace
  for every exported function. Struct methods keep their existing path. No retained
  cache, new synchronization policy, or module-interface format is introduced.
- `MicroPassHelpers.h` stops a negative dominance query once the parent walk reaches
  the queried node's reverse-postorder position. A strict dominator must precede its
  descendant. An independent graph-reachability oracle checks every node pair in a
  diamond with a loop and an unreachable tail, plus invalid node indices.

The final GUI profile attributes 16.03% to SSA build and 7.02% to SSA rename; the
constant-allocation writer is absent from its top 100 inclusive symbols. Public
overload collection is likewise absent from the final OGL profile's top symbols.
These confirm the local hotspots were removed; the loaded end-to-end timings below
must still be judged separately. The dominance change does not relax optimization
or alter the dominator relation.

The discarded SSA-storage experiment is preserved in
[ssa-storage-experiment.patch.gz](ssa-storage-experiment.patch.gz). Three loaded A/B pairs
gave median B/A wall/CPU ratios of 0.897/0.951 for GUI and 1.085/1.046 for Pixel;
Pixel resident peak rose to 1.029 times the preceding compiler. GUI's individual
times varied too widely to establish a benefit. The patch was reverted rather than
accepting a memory increase on that evidence. Incremental SSA analysis and entry
snapshot copying remain investigation leads in `compiler.optimization.029`.

## Validation observations

The existing seven native benchmark programs were compiled by both frozen Release
compilers in program `release`, then run with one warm pair and three alternating
measured pairs on the benchmark's six-performance-core mask. Every checksum matches.
The loaded median paired kernel ratios B/A are wordfreq 1.052, csvagg 0.999,
sha256 1.015, dijkstra 0.933, raytrace 1.000, leven 0.944, and chacha 0.878
(geometric mean 0.973). This does not establish a generated-code speedup; it checks
that the compile-speed changes have no observed systematic runtime penalty on these
programs. See [raw native samples](native-final-loaded.json) and
[native-summary.json](native-summary.json). It is not a replacement for a quiet,
recorded full benchmark campaign.

The retained compiler is build 393. Its final DevMode-compiler campaign passed all
644 C++ tests, the compiler language/JIT/native/workspace suites, and all 2,155
standard-module tests in both program configurations (529 Pixel and 709 GUI).
Both native-suite configurations passed 3,018 tests. The final four Capture actual
PNG hashes match the baseline exactly; see `validation/final-dm-golden-comparison.json`.

Fresh baseline DevMode and Release campaigns both reached the same existing four
Swag Capture menu golden failures, recorded before this task as `app.capture.026`.
The 392 candidate DevMode campaign passed the compiler language/native suites and all
2,155 standard-module tests in both program configurations, including 529 Pixel and
709 GUI tests. It reached precisely the same four Capture failures; their actual PNG
SHA-256 hashes exactly match the baseline. No goldens were promoted.

The generated foreign-export attributes of `core` (193), `ogl` (1,298), `pixel`
(127), and `gui` (44) are identical between the baseline and the 392 candidate.
All six full dependency warmups in the final 390/393 comparison likewise preserve
those exact attributes; see [final-api-export-names.json](final-api-export-names.json).
Adjacent borrow-summary attributes on five struct methods varied; the struct-method
lookup branch is unchanged. Four complete rebuilds with the same baseline executable
confirmed that both `Core.Math.Curve.addKey` overloads sometimes omit their borrow summary:
three snapshots contained it and one did not. This is a preexisting publication defect,
recorded as `compiler.core.032`; the underlying ordering cause remains unisolated.

The full campaign stops at Capture, so later rungs must be reported separately;
reaching that known failure is not a claim that every repository test ran.
The final Release campaign stopped earlier at the transient Pixel readback failure
described below. The queued complete standard-module reruns after restoring the
original test harness were not started before the noon cutoff. The earlier final
DevMode campaign and the independent Release results remain the validation evidence;
this report does not claim a completely green full Release campaign.

Commands for the baseline and final full campaigns were, in their respective
frozen compiler states:

```powershell
bin/swc.dm.exe --num-cores 6 tools/tests.swgs dm --all-cfg --num-cores 6
bin/swc.exe --num-cores 6 tools/tests.swgs --all-cfg --num-cores 6
```

Both final compiler binaries were rebuilt from retained sources. The trial 394
SSA-storage patch and its extra unit test were reverted before the final DevMode
build; the final Release executable was restored from the frozen build 393.

The final Release campaign additionally encountered a lost OpenGL readback in Pixel's
stroke-parity test. The exact same executable then passed all 17 parity tests. The
existing retry detector compared RGB but ignored alpha: the saved failure has only
3,923 pixels above the RGB threshold, below the 6,144-pixel trigger, but 11,537 when
alpha is included. A new CPU-only test with an opaque dark image reproduces this
detector defect with the baseline 390 compiler (one selected test, one failure).
An experimental alpha check passed all 18 selected Release parity tests and all
2,156 standard-module Release tests. DevMode then exposed another retry defect:
recreating a window with the same class identifier fails `RegisterClassA` with
`Class already exists`. Distinct attempt identifiers avoid that error, but the
opaque-backdrop parity test still reported five failed readbacks. This experiment
was reverted: its handling of legitimate alpha differences needs further investigation.
The unapplied [patch](pixel-readback-experiment.patch.gz) and validation logs preserve
the evidence, tracked as `std.pixel.025`. No Pixel implementation or test changes
are retained in the final compiler patch.

## Reproducing the comparisons

The scripts in this directory locate their enclosing `swc.sln` and reuse
`bench/winproc.py` and the existing benchmark workloads. Keep frozen baseline and
candidate Release executables beside that worktree's runtime. The private module
mirror is `.tmp/speed/profile/std`: copy each `git ls-files bin/std` entry there,
preserving its path relative to `bin/std`. Do not copy generated `.output` or `.dep`
trees. The full dependency warmup below rebuilds each binary's own artifacts.

```powershell
python bench/results/compilation/20260907/compare.py --a bin/swc.baseline.exe --b bin/swc.dominance.exe --label final-modules-pinned-loaded --reps 3 --modules gui,pixel,ogl,core --warm-module gui --rebuild-warm --pin --max-cpu 65
python bench/results/compilation/20260907/compare.py --a bin/swc.baseline.exe --b bin/swc.dominance.exe --label gui-fixed-dependencies --reps 5 --modules gui --warm-module gui --rebuild-warm --fixed-dependencies --pin --max-cpu 35
python bench/results/compilation/20260907/native_bench_ab.py --a bin/swc.baseline.exe --b bin/swc.dominance.exe --label native-final-loaded --reps 3 --max-cpu 65
python bench/results/compilation/20260907/bench_guard.py --compile --swc C:/Perso/swag-lang/swc-speed-20260907/bin/swc.baseline.exe --against C:/Perso/swag-lang/swc-speed-20260907/bin/swc.exe --reps 3 --cores 6
```

Run these commands serially. Use `--max-cpu 15` for the focused scripts when
the machine can remain quiet. The normal 65% ceiling is used here only to retain
explicitly loaded evidence within the user's noon time limit. The last command
uses the repository's existing `bench/compile.py` A/B loop, including documentation,
formatting, no-op, and touched-file workloads, with an added existing hello recipe.
It writes docs and formats copies under private benchmark outputs. Its one-file
touch changes `core/src/text/utf8.swg`'s timestamp; save and restore that timestamp
around the command. The campaign wrapper did so in a `finally` block.

These focused comparisons are not an accepted full cross-toolchain campaign and
are not appended to `bench/history.json`. The latter's quiet/drift gate would be
misrepresented by admitting this loaded series as a normalized historical result.

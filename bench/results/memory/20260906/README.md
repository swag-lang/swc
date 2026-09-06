# Compiler memory campaign - 2026-09-06

The sanitizer storage candidate is saved on `codex/memory-20260906`. It is **not accepted as a
performance win**: repeated measurements with sufficiently low background load did not complete
within this campaign's time window. The compiler changes remain on the isolated branch pending
that acceptance. Functional checks passed through the same pre-existing GUI5 smoke failure as
the baseline; neither full campaign is green. The four memory/time targets are not established.

## Revisions and changes

- Baseline: `89c7c0e7a`, compiler build 381.
- Storage candidate: `717ec4db6`, compiler build 383, including `67cb4a59a`.
- Store sanitizer flow states only at chain heads, instead of constructing four hash maps for
  every instruction.
- Omit default register facts and unknown stack values; absence already means Unknown. Keep
  register provenance and known values, and remove zero facts when they become unknown.
- The branch also integrates the positive-floating-zero legalization already on master,
  using compiler build 384. Performance comparisons use the frozen 381/383 binaries to isolate
  the sanitizer changes. Binary SHA-256 values are in [validation.json](validation.json).

Both measured binaries were built in Release with the normal optimizations, plus PDB and map
output for external profiling ([MSBuild properties](release-profile.props), imported with
`/p:ForceImportBeforeCppTargets=<absolute properties path>`). All compiler commands use six workers; MSBuild uses `/m:6` and
`/p:SwcCompileJobs=6`. The host is an Intel Core Ultra 9 185H with about 32 GiB of physical memory.
Builds are unpinned. No tracking or profiling branch was added to the compiler.

## Measurement protocol and limits

The metric is Windows `GetProcessMemoryInfo` PeakWorkingSetSize, read every 2 ms while the
compiler is alive. Wall time and process CPU time come from the repository's suspended-process
and job-object harness. Each repetition runs A/B, then B/A on the next repetition; each command
uses `--rebuild --silent --num-cores 6`. Raw commands and samples are retained below.

The initial baseline has three repetitions of every workload. The acceptance attempt requires
CPU at most 15% and the standard memory admission before each command. Other campaigns kept
starting work on the shared host; a low-load admission also cannot prevent a foreign process
from starting during the sample. An initial quiet attempt produced one unpaired baseline sample; it is kept in
[abandoned-quiet-attempt.json](abandoned-quiet-attempt.json). The final quiet retry focuses on
core devmode, core release and hello. A separate exploratory attempt uses the normal CPU limit of
65% and the same memory checks. Those observations describe a loaded machine and do not prove
unchanged compile time. No missing pair is filled from the earlier baseline window.
[Rejected admission observations](admission-observations.json).

Ratios are medians of complete same-repetition pairs, not ratios between minima. The raw paired
ratios expose the spread. MiB means 1,048,576 bytes; target labels follow the campaign's existing
MiB convention. The longer-term hello budget in compiler.core.005 is 40 MiB, tighter than the
50 MiB prompt target shown here.

## Initial baseline

These measurements preceded the first compiler edit; they are not the acceptance comparison.
[Raw baseline samples](initial-baseline.json).

| Workload | Peak RSS MiB | Wall ms | CPU ms |
|---|---:|---:|---:|
| core_devmode | 505.5 | 2408.7 | 11031.2 |
| core_release | 349.4 | 2096.1 | 9484.4 |
| hello | 58.1 | 121.4 | 468.8 |
| wordfreq | 59.2 | 126.4 | 437.5 |
| csvagg | 59.7 | 124.6 | 453.1 |
| sha256 | 59.3 | 124.2 | 562.5 |
| dijkstra | 59.4 | 129.3 | 500.0 |
| raytrace | 57.3 | 112.9 | 468.8 |
| leven | 60.5 | 119.6 | 421.9 |
| chacha | 64.2 | 147.6 | 437.5 |

## Quiet comparison

| Workload | Pairs | A RSS MiB | B RSS MiB | Target MiB | A wall ms | B wall ms | Paired wall B/A | Paired CPU B/A |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| core_devmode | 0 | n/a | n/a | <250 | n/a | n/a | n/a | n/a |
| core_release | 0 | n/a | n/a | n/a | n/a | n/a | n/a | n/a |
| hello | 0 | n/a | n/a | <50 | n/a | n/a | n/a | n/a |
| wordfreq | 0 | n/a | n/a | 69 | n/a | n/a | n/a | n/a |
| csvagg | 0 | n/a | n/a | 69 | n/a | n/a | n/a | n/a |
| sha256 | 0 | n/a | n/a | 69 | n/a | n/a | n/a | n/a |
| dijkstra | 0 | n/a | n/a | 69 | n/a | n/a | n/a | n/a |
| raytrace | 0 | n/a | n/a | 69 | n/a | n/a | n/a | n/a |
| leven | 0 | n/a | n/a | 69 | n/a | n/a | n/a | n/a |
| chacha | 0 | n/a | n/a | 69 | n/a | n/a | n/a | n/a |

[Raw quiet samples and paired ratios](quiet-measurements.json). Rows with fewer than repeated complete pairs are incomplete.

## Exploratory comparison

| Workload | Pairs | A RSS MiB | B RSS MiB | Target MiB | A wall ms | B wall ms | Paired wall B/A | Paired CPU B/A |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| core_devmode | 1 | 486.0 | 432.7 | <250 | 5934.6 | 5932.8 | 1.000 | 0.947 |
| core_release | 1 | 334.4 | 330.2 | n/a | 7647.3 | 6904.4 | 0.903 | 1.068 |
| hello | 1 | 56.4 | 53.0 | <50 | 387.2 | 296.0 | 0.764 | 0.757 |
| wordfreq | 1 | 53.8 | 55.0 | 69 | 2127.1 | 405.4 | 0.191 | 0.233 |
| csvagg | 1 | 60.5 | 56.6 | 69 | 386.3 | 393.9 | 1.020 | 1.057 |
| sha256 | 1 | 58.9 | 54.5 | 69 | 350.2 | 257.2 | 0.734 | 0.634 |
| dijkstra | 1 | 62.0 | 55.0 | 69 | 221.7 | 139.1 | 0.627 | 0.615 |
| raytrace | 1 | 56.5 | 56.6 | 69 | 213.0 | 173.8 | 0.816 | 0.870 |
| leven | 1 | 59.7 | 57.1 | 69 | 173.0 | 2561.3 | 14.803 | 9.585 |
| chacha | 0 | n/a | n/a | 69 | n/a | n/a | n/a | n/a |

[Raw exploratory samples and paired ratios](exploratory-measurements.json). Rows with fewer than repeated complete pairs are incomplete.

## External heap attribution

An external Frida 17.17 sampler hooks operator new, nothrow new, allocThrow and mi_free, records
native Windows stacks, and samples live allocations every 32,768 allocated bytes. The snapshot
is taken at the observed working-set peak during the core devmode rebuild.

| Observed live requested memory | Baseline MiB | Candidate MiB |
|---|---:|---:|
| Sanitizer | 57.7 | 35.8 |
| Arenas with mixed semantic/symbol ownership | 50.5 | 50.7 |
| Other sampled C++ heap | 61.9 | 65.8 |

About 74.5% of sampled baseline stack-map node bytes held Unknown. No such node is observed in
the candidate snapshot. These are weighted estimates of live requested bytes, not resident
bytes. Instrumentation changes both timing and allocation schedules; its working-set figures
are not performance results. Direct proximity/virtual pages, retained freed allocator pages,
and inlined entry points are not fully accounted for. The AST/types/symbols/constants/Micro
resident split therefore remains incomplete. Do not subtract these estimates from OS RSS.
[Sampling metadata and largest native stacks](heap-sampling.json).

The two initial lifetime suspects were checked in the baseline source: finished CodeGen jobs
already reset Sema/CodeGen state in `CodeGenJob::releaseSemaAndCodeGen`, and
`SymbolFunction::emit` already calls `MicroBuilder::releaseMemory` after emission. This campaign
does not add a second release to those paths. AST/proximity page ownership still needs a fuller
external trace before changing its lifetime.

## Validation

Before and after the storage changes, both compiler executables ran
`tools/tests.swgs --all-cfg` with the six-worker cap. All four attempts passed the compiler and
workspace suites, 2,132 standard-module tests, 459 application tests and 458 reference tests in
both program configurations, then the release script smokes. They stopped in the release
examples at GUI5 with `0xC0000005`; later stages were not reached. The candidate and baseline
Windows events identify the same fault RVA, `0x1BDC0`.

The integrated build 384 passed both C++ builds, 636 C++ tests, 39 sanity tests, and the new
floating-zero native regression with both compiler executables in both program configurations.
[Validation matrix and binary identities](validation.json).

The GUI5 failure was reduced with the unchanged baseline compiler to an inlined conditional
returning a four-byte structure: generated code dereferences `0xFFFFFFFF` as an address.
[Standalone reduction](gui5-reproducer.md); the next fix remains in
[std.gui.053](../../../../backlog/std.gui.md).

## Acceptance still required

Repeat every A/B workload on a quiet host and establish the paired wall/CPU spread before
merging the compiler changes. Preserve the hard constraint: a memory reduction that costs
compile time is rejected. Then extend external accounting to proximity allocations and retained
allocator pages before selecting the next memory reduction. The sanitizer sample alone does
not explain the remaining core working set or establish the 250 MiB target.

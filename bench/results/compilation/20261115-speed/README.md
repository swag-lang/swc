# Compilation speed, 2026-11-15 to 2026-11-16

The retained batch removes repeated compiler work while preserving optimization
eligibility, generated-code policy, runtime guards and cache fingerprints. The
baseline is commit `45356a61c9a74be6bd1f8aa73ccdc8353a225b4c`.

## Retained changes

| Area | Work removed | Equivalence and safety boundary |
| --- | --- | --- |
| [GNU x86-64 SHA-256](../../../../src/Support/Math/Sha256.cpp) | Portable SHA rounds when the processor provides SHA instructions | Dispatch requires SHA, SSSE3 and SSE4.1. ISA targeting is confined to the existing accelerated block function, with the software fallback retained. SHA-256 output and multipart padding are unchanged. |
| [Post-RA private spill sinking](../../../../src/Backend/Micro/Passes/Pass.PostRAPeephole.cpp) | A fresh entry-to-reader CFG traversal for every candidate label | Build the existing instruction dominator tree lazily once for the same immutable graph. Dominance answers the same path-exclusion question; entry-unreachable readers keep the old vacuous result. Stack depth, private-slot ownership, value stability, alias checks, walk limits and all rejection conditions remain in place. The function returns immediately after its first mutation. |
| [Semantic symbol-map collection](../../../../src/Compiler/Sema/Match/Match.cpp) | Repeated linear membership scans of previously collected maps | A fresh local `PointerSet` indexes membership for one lookup. The ordered vectors still determine discovery order and priorities, including recursive struct/impl/using discovery. No shared or thread-local lookup state is introduced. |
| [Machine-code cache constant leaves](../../../../src/Backend/Micro/MachineCodeCache.cpp) | Owned leaf-key allocations and payload copies | Keys view immutable, append-only constant storage and cache a lookup hash. Full equality still compares alignment, length and every byte, including bytes after NUL. Dictionary hash collisions cannot merge unequal leaves. Relocated graphs retain allocation identity, cycles, sharing and interior offsets; the serialized SHA-256 fingerprint is unchanged. |
| [Machine-code cache source ordinals](../../../../src/Backend/Micro/MachineCodeCache.cpp) | Repeated dictionary lookups for consecutive instructions with the same source binding | Once assigned, a source ordinal never changes during the input walk. The local memo reuses that ordinal; validity and no-step flags are still serialized for every instruction. Invalid source gaps and revisiting older bindings preserve the original sharing topology. |

No compiler version change, new global ISA requirement, optimization-pass budget
reduction, inlining/vectorization threshold change, or safety/sanity preset change
is included. Experiments without a reproducible net benefit were discarded.

## Whole-batch measurements

These compare the complete retained batch with the original compiler. Component
experiments are not added together. Both compilers used for timing were built with GCC 14.2.0 in
Release on Linux x86-64, using the same native build settings (`x86-64-v3`). The
managed machine had a four-CPU cgroup quota, 16 GiB memory and an AMD EPYC 9V74.
Program configuration is independent of compiler configuration.

Each forced-rebuild comparison alternates A/B and B/A, uses frozen workspace
sources, separate temporary/cache roots for each compiler, and no concurrent
compiler/test workload. Three compiler workers are used unless the table says
one. Filesystem caches are warm; `--rebuild` forces module rebuilding but does not
promise empty operating-system or machine-code caches. Wall time is measured
around the process; CPU time and peak RSS come from `wait4`.

| Workload | Program config | Workers | Pairs | Baseline s | Final s | Wall reduction | CPU reduction | RSS final/base | Faster pairs |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| std/core | devmode | 3 | 13 | 3.940 | 3.857 | 1.6% | 1.4% | 1.002 | 9/13 |
| std/gui | devmode | 3 | 9 | 29.564 | 26.457 | 11.0% | 10.6% | 0.997 | 9/9 |
| std/gui | devmode | 1 | 5 | 77.452 | 67.457 | 13.0% | 13.0% | 1.001 | 5/5 |
| std/gui | release | 3 | 9 | 19.560 | 18.717 | 3.8% | 3.9% | 0.994 | 9/9 |
| std/gui | release-safe | 3 | 9 | 33.423 | 27.990 | 15.9% | 12.8% | 1.002 | 9/9 |
| apps/swagscope | devmode | 3 | 4 | 53.626 | 48.815 | 9.2% | 8.9% | 1.007 | 4/4 |
| std/(all modules) | devmode | 3 | 7 | 44.813 | 39.882 | 10.2% | 9.9% | 1.013 | 7/7 |

The gain is `100 * (1 - median(final_i / baseline_i))` over paired rounds.
Absolute timings are separate medians, so their ratio need not equal the paired
median ratio. Small changes, particularly on short `core` builds, remain sensitive
to scheduler noise. Results describe these workloads and this host, rather than a
universal compile-time improvement.

| Edit-loop workload | Pairs | Baseline ms | Final ms | Wall reduction | CPU reduction | RSS final/base |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `core_delta` | 21 | 3270.3 | 3156.2 | 2.6% | 2.8% | 0.997 |
| `core_noop` | 21 | 11.1 | 10.8 | 0.4% | 1.2% | 1.000 |
| `core_rebuild` | 21 | 3816.7 | 3696.0 | 3.4% | 3.5% | 0.997 |
| `core_touch` | 21 | 1802.0 | 1682.0 | 6.6% | 6.5% | 0.997 |
| `hello_build` | 21 | 163.8 | 162.2 | 2.0% | 1.6% | 1.001 |

The edit-loop workloads use the repository's `bench/scripts/compile.py`, with
alternating order, isolated compiler installations, 21 pairs and three workers.
Primary edit-loop ratios come from the tool's final summaries, rounded to 0.001.
The per-round samples are parsed from its printed values, rounded to
0.1 ms / 0.1 MiB; the JSON also keeps ratios recomputed from those rounded
samples. `TMPDIR` was unset so the tool's per-workload `TMP`/`TEMP` roots were
honored. The approximately 11 ms `core_noop` case shows no material speed change.

### Incomplete runs

One initial Release GUI measurement stopped in the unchanged baseline compiler
with `expected a value expression here` at `core/src/text/regexp/prefilter.swg:795`.
Earlier rounds had compiled the same input successfully. Its successful prefix
is excluded from the timing conclusions. A second series was interrupted by an
environment restart; its prefix is also excluded. Both remain in
[measurements.json](measurements.json). Later complete series use fresh output
roots. Single-pair pilots are recorded separately and excluded from the tables.

## Generated-code and safety validation

Final validation used the frozen Release and DevMode compiler binaries:

- All **1,836 C++ tests**, including the full filesystem group and cache/corruption
  tests. New coverage checks unaligned/multipart SHA input, relocated constant
  graphs, leaf alignment/embedded NUL/interior offsets, and repeated source
  bindings across invalid gaps and flag changes.
- Semantic suites with both compiler binaries: **313 ordinary files and 381
  expected-error files** each.
- Native suite in both execution modes: **4,083 tests** in DevMode and **4,045**
  in `release-safe`; safety suite **165** in each configuration; sanity **92**.
- Workspace suite: **56/56 stages**; core functional native tests **975**;
  pixel WebP **20**; GUI PDF CPU rendering **14**.
- Explicit DevMode Micro verification of `private_spill_cold_call.swg` and
  `carried_spill_cache.swg` in both DevMode and `release-safe`.
- **43 cache-key observations** identical between the original and final cache
  serializers, using the same final tests and explicit test compiler identity.
  This includes the new layout, graph and source-sharing cases.
- Hardware and forced-software SHA-256: **563 boundary/random vectors per path**
  compared with Python `hashlib`, including multipart splits at 0, 1, 55, 64 and
  65 bytes.

All twelve benchmark programs were captured against the original compiler in
**Release, DevMode and `release-safe`**, for **36 task/configuration comparisons**.
All runtime checksums match. Complete normalized Micro instruction sequences
match, including shared runtime functions and loop bodies. Duplicate printed
specialization names are compared as complete-body multisets within the same
name family; printed `#2` order can vary, also reproduced baseline-vs-baseline.
This comparison does not substitute instruction counts for instruction equality.

Only proven metadata is normalized: process pointer operands, source-derived
runtime lambda / `__run_expr` IDs matched by source location, and the raw `TypeRef`
passed in SysV RSI to `persistCompilerRunValue` at `runtime/core.swg:669`.
That argument is compiler JIT metadata. The R9 allocation size (`0x20`), all other
arguments, instruction order, branches, memory operations and guards remain in
the comparison. The DevMode auditor was adjusted for its different return-buffer
register and argument scheduling; captures and compiler sources were unchanged.
The initial strict auditor failure is retained in the external logs. Negative
controls also check that the auditor rejects an equal-count immediate change, a
changed branch condition and a changed JIT allocation size, while accepting the
identified TypeRef metadata change.

No generated-code runtime speedup is claimed. The evidence is unchanged optimizer
choices, unchanged guards, successful functional/safety execution and identical
normalized instruction sequences on the benchmark corpus. This is bounded
validation evidence, not a proof for every possible program.

## Discarded late experiment

An external probe combined consecutive source-flag writes and the fixed instruction
header into fewer cache-serialization appends, without intentionally changing the
byte stream. Against the retained batch, eleven paired edit-loop rounds gave wall /
CPU ratios of **1.010 / 1.017** for `core_rebuild`, **1.020 / 1.023** for `core_delta`,
and **0.981 / 0.998** for `core_touch`. It had no net benefit and was not applied.
These are incremental experiment ratios, not another comparison with the original
compiler. See [rejected-experiment.json](rejected-experiment.json).

## Data and reproduction

- [measurements.json](measurements.json): per-run commands, binary hashes, exit
  status, wall/CPU/RSS, paired ratios, and excluded partial/pilot runs.
- [edit-loop.json](edit-loop.json): the official edit-loop samples and summaries.
- [validation.json](validation.json): exact suite commands, counts, cache keys,
  SHA checks and all per-task Micro audit results.
- [audit-micro.py](audit-micro.py): the constrained full-instruction auditor;
  run it with a saved `microdiff.py` output directory as its argument.
- [provenance.json](provenance.json): baseline commit, frozen source-diff digest,
  native compiler version and exact binary hashes.

All probes, binary copies, captures and full logs are outside the checkout at
`/workspace/swc-opt-20261115`. C++ source files were frozen before final validation
and measurement; the source-diff digest was checked again at closeout. Build
outputs and instrumentation are not part of this change.

To repeat a forced-rebuild sample, use the corresponding command and worker cap
from `measurements.json`, with separate `SWAG_PATH` and `TMPDIR`/`TMP`/`TEMP` roots.
Run the two compiler roles sequentially in alternating order. For the edit loop:

```sh
python3 bench/scripts/compile.py --swc /absolute/baseline/swc \
  --against /absolute/final/swc --swc-cores 3 --reps 21 \
  --only core_rebuild,core_noop,core_touch,hello_build,core_delta
```

For generated-code inspection, save each program configuration separately:

```sh
python3 bench/scripts/microdiff.py --base /absolute/baseline/swc \
  --new /absolute/final/swc --cfg release --cores 3 --verbose \
  --save-dir /absolute/micro-release
python3 bench/results/compilation/20261115-speed/audit-micro.py \
  /absolute/micro-release
```

Repeat for `devmode` and `release-safe`. Inspect every reported difference;
source-derived IDs and JIT metadata require the constrained normalization
explained above, not a blanket removal of immediates or function names.

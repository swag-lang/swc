# Runtime allocator comparison, 2026-10-18

The runtime allocator's header lists use address hashing that distributes aligned reservations across
all eight locks. Local front-cache frees avoid the shared live-byte budget read, and front lookup
stops at an exact fit. The regression checks reservations spaced from 64 KiB through 1 GiB.

The final `large:4` measurement improves from **1041.4 to
842.5 ns/op**, against **867.4 ns/op**
for mimalloc. Its identical-binary control differs by only
+0.4%.

The raw fourteen-workload geometric means are 1.199 -> 1.073 times mimalloc's time.
**Do not interpret this as a validated aggregate speedup or allocator parity:** the same-binary controls
move by up to 27.6%, with substantial interference on `trees` and `realloc`.
The control's geometric change is -5.5%. The small-allocation gap remains open.

## Protocol

- Five rotating rounds in fresh processes, through `bench/allocbench.py` and `bench/winproc.py`, pinned
  to the benchmark's performance cores. Every payload is touched. Times are medians.
- Before and after use the same DevMode compiler binary, program configuration `release`, six compiler
  workers, benchmark sources, and temporary runtime/standard-library resource paths. Only
  `bin/runtime/allocator.swg` differs. Imported modules were rebuilt for each binary.
- The baseline runtime comes from `df4f9ebd3e`. The extra `control` column runs the exact same executable
  as `before`; it exposes scheduling and frequency drift. mimalloc is the vendored version built once
  with MSVC `/O2 /DNDEBUG`. This is a shared-machine session, not a quiet-machine parity claim.
- Short `spread` timings include thread creation. Concurrent workloads are scheduling-sensitive;
  consult the raw controls and worker times before attributing small differences. The remaining
  small-allocation gap is not closed by these header-path changes.

## Results

| Workload | Before ns/op | After ns/op | mimalloc ns/op | Change | Control drift | After / mimalloc |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `large:4` | 1,041.4 | 842.5 | 867.4 | -19.1% | +0.4% | 0.971 |
| `pair` | 20.0 | 17.9 | 9.4 | -10.7% | -5.9% | 1.904 |
| `trees` | 29.6 | 24.4 | 17.8 | -17.8% | -24.5% | 1.367 |
| `churn` | 63.2 | 63.8 | 41.9 | +0.9% | +2.7% | 1.521 |
| `medium` | 62.3 | 66.7 | 84.0 | +7.0% | +2.1% | 0.794 |
| `large` | 1,409.5 | 1,400.0 | 3,621.7 | -0.7% | -4.3% | 0.387 |
| `realloc` | 52,834.4 | 13,263.2 | 11,748.9 | -74.9% | -27.6% | 1.129 |
| `spread` | 40,016.7 | 53,208.3 | 44,082.5 | +33.0% | -6.6% | 1.207 |
| `grow` | 8.1 | 8.2 | 7.4 | +1.3% | +4.2% | 1.108 |
| `spread:8` | 743.8 | 619.8 | 693.8 | -16.7% | -9.2% | 0.893 |
| `churn:4` | 10.9 | 11.4 | 7.8 | +4.8% | -1.7% | 1.458 |
| `medium:4` | 11.1 | 11.2 | 11.9 | +0.7% | +0.5% | 0.944 |
| `xfer:2` | 61.0 | 64.3 | 57.1 | +5.4% | -2.2% | 1.126 |
| `xfer:4` | 69.8 | 73.7 | 68.0 | +5.6% | +2.9% | 1.084 |

Raw samples, worker times, peak working sets, commit peaks, OS call counts, executable/source hashes,
and identical-binary controls are in [comparison.json](comparison.json).

## Validation

- MSBuild DevMode, `/m:6 /p:SwcCompileJobs=6`; compiler C++ tests: 1,463 passed.
- `swc.dm` native allocator selection (`--file-filter allocator`): 146 tests in `devmode`,
  105 in `release`, each through JIT and native execution.
- `core`'s `alloc.test.swg` and `allocator.concurrent.test.swg`: 8 tests in `devmode`, 7 in `release`.
- The Release compiler also passed the 105 allocator tests in program configuration `release`.
- The shard-distribution regression was observed failing before the correction, including the
  stronger-alignment case, and passes with the final multiplicative hash.
- The repository/backlog/link validator passes, and `git diff --check` is clean.

Every build/test command passed the machine-load admission check and capped compiler workers at six.
No compiler source or public allocator API change is retained. The compiler build number is unchanged.

## Retention

Three rotating rounds, MiB of working set; lower is better.

| State | Before | After | mimalloc |
| --- | ---: | ---: | ---: |
| Idle | 43.36 | 43.36 | 43.79 |
| After purge delay | 15.21 | 15.21 | 43.80 |
| After trim | 10.71 | 10.70 | 4.30 |

The bounded post-trim current-page retention remains above mimalloc; this change does not alter that policy.

# mimalloc large object pages, 2026-11-17

The default for `MI_ENABLE_LARGE_PAGES` is now off. In mimalloc, this selects regular
large-page pools for allocations from 64 KiB through 512 KiB; disabling it sends those
allocations through the singleton path. The source already notes that random block sizes can
leave these pools partially occupied.

## Comparison

The baseline was built from `c072965` with GCC 14. Initial candidates from that source set
`MI_ENABLE_LARGE_PAGES=0` consistently for the precompiled header and every C++ translation
unit. After changing the header default, a fresh DevMode candidate was built without a macro
override and tested again. `compile.py` ran six workers, alternating baseline (A) and candidate
(B). DevMode has ten pairs across the initial and final-source five-pair sessions. Release has
ten pairs across two five-pair sessions using the same binaries and installations. Peak values
below are the maximum Linux process RSS seen in each series. Ratios are paired median B/A, so
values below 1 favor the candidate.

| Compiler | Workload | Peak RSS A → B (MiB) | Peak ratio B/A | Wall ratio B/A | CPU ratio B/A |
| --- | --- | ---: | ---: | ---: | ---: |
| DevMode | `core_rebuild` | 762.1 → 537.4 | 0.702 | 0.968 | 0.970 |
| DevMode | `hello_build` | 287.1 → 112.9 | 0.412 | 0.795 | 0.859 |
| Release | `core_rebuild` | 671.8 → 528.3 | 0.781 | 0.937 | 0.962 |
| Release | `hello_build` | 185.4 → 111.6 | 0.605 | 0.907 | 0.966 |

The final DevMode candidate passed the full C++ suite: 1,859 tests in 80.65 seconds. The baseline
and candidate produced matching output checksums for all 12 `microdiff` tasks in both
configurations. Micro listings still report changed function counts for duplicate generic names
and different hashes for same-count `__run_expr` bodies; the checksum comparison does not prove
exact listing identity. Both Release hello binaries ran successfully and printed identical output.
Their binary hashes differ. The 25 generated core API `.swg` files and `core.swg` match byte for
byte, while `core.a` differs.

## Limits

These are Linux process RSS and wall-time observations, not Windows working-set or commit
measurements. The workspace has no Wine, Windows SDK, or Windows import libraries, so the Windows
Swag Capture workload and the campaign's absolute Windows targets could not be measured here.
These Linux numbers do not establish whether the Windows targets (250 MiB for `core_rebuild`,
50 MiB for `hello_build`) are met.

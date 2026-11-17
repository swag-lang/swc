# mimalloc large object pages, 2026-11-17

## Decision

The change to default `MI_ENABLE_LARGE_PAGES` to `0` was reverted. The initial large memory
reductions were measured against baseline `c072965` while the candidate source advanced with
remote `master`; that comparison is exploratory and cannot attribute the differences to this
allocator setting. A same-source DevMode comparison on `1eb0629d1d` found only a small RSS
difference on `core_rebuild` and no reduction on `doc_std` or `hello_build`. No Windows working
set or commit measurement was available, so the campaign targets were not validated.

## Exploratory measurements (not a controlled source comparison)

The original series built the baseline from `c072965` and later candidates from a newer source
revision. `compile.py` used six workers. These numbers explain why the setting was investigated,
but they are not evidence that the setting caused the change:

| Configuration | Workload | Peak RSS A → B (MiB) | Paired RSS ratio | Paired wall ratio | Paired CPU ratio |
| --- | --- | ---: | ---: | ---: | ---: |
| DevMode | `core_rebuild` | 762.1 → 537.4 | 0.702 | 0.968 | 0.970 |
| DevMode | `hello_build` | 287.1 → 112.9 | 0.412 | 0.795 | 0.859 |
| Release | `core_rebuild` | 671.8 → 528.3 | 0.781 | 0.937 | 0.962 |
| Release | `hello_build` | 185.4 → 111.6 | 0.605 | 0.907 | 0.966 |

## Same-source DevMode comparison

Both binaries were built from `1eb0629d1d`, with the header setting as the only source difference:
A used `MI_ENABLE_LARGE_PAGES=1`; B used the default `0`. The runs alternated, used six compiler
workers, and had separate standard-library installations. RSS columns show the highest Linux
process RSS observed per compiler across three runs. Ratios are the median of paired B/A values.

| Workload | Peak RSS A → B (MiB) | Paired RSS ratio | Paired wall ratio | Paired CPU ratio |
| --- | ---: | ---: | ---: | ---: |
| `doc_std` | 1971.5 → 1981.8 | 0.997 | 0.785 | 1.015 |
| `core_rebuild` | 528.3 → 525.7 | 0.954 | 0.984 | 0.954 |
| `hello_build` | 113.4 → 114.1 | 1.003 | 0.893 | 0.874 |

The wall ratio on `doc_std` varied sharply between pairs; CPU was 1.5% higher, within the
observed run-to-run noise. `core_rebuild` RSS improved by about 4.6%; `hello_build` and `doc_std`
showed no meaningful RSS reduction. This did not justify retaining a global allocator-default
change. A separate 256 KiB threshold trial was incomplete and showed a large RSS increase in its
one isolated pair, so it was not retained.

A runtime purge trial set `MIMALLOC_ARENA_PURGE_MULT=0` for the candidate and used the same
compiler binary for A and B. Across two pairs, `doc_std` RSS fell 15–18% while wall and CPU time rose 12–18% and 12–16%;
`core_rebuild` RSS fell 13–14% while wall and CPU rose 8–25% and 12–21%. This option also
failed the compile-time constraint and was not retained.

## Validation and limits

The restored-default (`MI_ENABLE_LARGE_PAGES=1`) DevMode binary from `1eb0629d1d` passed the
full C++ suite: 1,859 tests in 88.1 seconds. The earlier default-off candidate also passed 1,859
C++ tests. Microdiff output checksums matched for 12 tasks in DevMode and Release, although
duplicate generic function names and `__run_expr` bodies left listing-level differences
unresolved. These checks do not validate the latest remote source revision.

All memory figures here are Linux process RSS, not Windows working set or committed memory. The
workspace did not have Wine, a Windows SDK, or Windows import libraries, so Windows Swag Capture
and the absolute Windows targets (250 MiB for `core_rebuild`, 50 MiB for `hello_build`) were not
measured.

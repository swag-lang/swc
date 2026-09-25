# Compilation speed, 2026-09-25

The campaign used an isolated worktree, the Release compiler and six workers.
The retained code change moves `MicroStorage::ptr` into its header so callers
can inline its unchanged validity checks. In a branch-simplification object,
references to that helper fell from 258 to 48. Focused native and random JIT
tests passed, as did a complete Release campaign before integration into
`master`. Alternated timing runs did not isolate a reliable percentage gain;
this is a structural saving below the measurement floor.

Latest five-run medians on merged build 1150:

| Workload | Wall | CPU | Peak resident | Target |
| --- | ---: | ---: | ---: | ---: |
| Full `std/core` rebuild | 2,241 ms | 9,406 ms | 582 MiB | <1,000 ms |
| Warm `std/core` no-op | 42 ms | 47 ms | 10 MiB | <100 ms |
| One `std/core` file touched | 1,935 ms | 9,141 ms | 565 MiB | diagnostic |
| Hello world through linking | 126 ms | 438 ms | 58 MiB | <50 ms |

Rejected trials: cumulative graph invalidation gating had inconclusive timings
under shared-machine load; skipping empty JIT relocation lists had no repeatable
whole-build gain; inlining all eight instruction-view methods removed calls but
regressed core rebuild CPU in two A/B series (1.077 and 1.148 candidate/baseline
median ratios). Their source changes were reverted.

The commits `eeaaf6077`, `605f12062`, `050706013`, `4d742f283`, `37322f448`
and `b50cc7681` belong to prompt 4 and predate the commit-prefix instruction.
Later campaign commits use `[prompt 4]` in their subjects.

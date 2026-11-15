# Conditional release may-use warning

## Round 1

| Check | Tests | Consumer sweep | Warning sites | Decision |
| --- | --- | --- | --- | --- |
| A local may hold a released pointer after a conditional release | `cwe416_use_after_free.swg`: the warning fires on the stale read; the kept-path read and post-rebind read stay silent. The retained allocator checks both runtime paths without touching physically freed storage. | `safety` and `sanity` pass. `std-core` and `std-audio` pass; compiling their shared core module reports two reads in `Threading.createSuspendedNative` after the branch that conditionally releases its state. The first standard-library sweep stopped later at the independently reproduced `gui/menu.anchors.swg` failures on both the current compiler and the pre-campaign compiler. | Three distinct source uses observed so far: one corpus use and two core thread-field reads. This is an early count, not the completed `bin/` count; examples, apps and reference have not yet been swept. | Keep the may fact separate from the must proof and report it as a warning. Continue the whole-tree sweep and triage each warning before calling the count complete. |

## Validation

- DevMode compiler: `safety` passed (JIT and native); `sanity` passed.
- DevMode standard consumer: `std-core` passed. `std-audio` passed with the two warnings above.
- Isolated GUI comparison: `std gui --test-file tests/cases/golden/menu.anchors.swg` fails with the same two tests on both `b3aec41590` and its parent `08f95f268f`; this is not attributed to the may-use analysis.
- `git diff --check` passed.

## Commit

- Integrated into remote `master` by `b457b0fa70` (after the campaign commit `dbc4b8f4c6`).

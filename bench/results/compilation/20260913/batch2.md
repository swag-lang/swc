# Second static micro-pass batch

Compiler build 527, source commit `e7079713e`, based on the first batch integrated
into master at `cf271ca2d`. Functional validation only: the user explicitly deferred
performance measurements until the final campaign.

| Change | Work removed | Preserved contract |
| --- | --- | --- |
| InstructionCombine initializes fresh-register counters at its first viable vector plan | Two whole-function operand scans for functions without vector construction | Initialization sees the same unmodified IR; rejected plans restore counters after initialization. |
| StrengthReduction checks the operation before CPU-flag scans | Strict scans for operations other than unsigned multiply, relaxed scans for unhandled operations, duplicate scan for add/sub zero | Same strict/relaxed flag rules, same transformation order. |
| Register allocation builds call summaries only at calls | Live-out unions at non-call instructions and unused concrete-register unions | Only calls contributed to these summaries; later scratch consumers reset their buffers. |
| Live intervals use binary searches in sorted events and ranges | Repeated linear searches from the beginning during allocation and splitting | Inclusive next-access and strict previous-access bounds, sorted split partitions, and sentinels stay identical. |
| Live interval construction drops unread scratch arrays | Two per-function allocations and zero fills | Neither array had a reader. |
| BranchSimplify shares a program layout across adjacent transforms | Rebuilding unchanged instruction/label positions after retargeting | It rebuilds after erasure before the adjacency-dependent transform; order is unchanged. |
| MemToReg keeps each slot's maximum access end | Rescanning all accesses for every overlap query | Accesses share their start; max(end) answers the same existential test, including wrapping ends and rejected slots. Costs 8 bytes per slot. |
| NaturalLoop counts members during discovery | A full membership-array scan per loop | Each membership transition from zero to one contributes once, including the header. |
| SSA skips predecessor lookup for successors without phis, otherwise uses binary search | Lookup on unused edges and linear search for every input of a large join | Predecessors are unique and sorted by block construction; input order is unchanged. |

Eleven added C++ tests cover allocation boundaries, vector-plan rollback, strict flags,
overlap and wrapping endpoints, branch-layout invalidation, repeated loop-body discovery,
and exact phi-input ordering at a 32-predecessor join. No new test translation unit.

Build 527 DevMode and all functional tests passed (each command exited with code 0):

- [DevMode build](batch2-build.log), MSBuild `/m:6 /p:SwcCompileJobs=6`.
- [C++ suite](batch2-cpp.log): 696 passed, including all 11 new tests.
- [Native devmode](batch2-native-devmode.log): 3,131 passed and generated executable passed.
- [Native release](batch2-native-release.log): 3,131 passed and generated executable passed.

The test commands were the same checkout-local `tools/unittests.swgs dm` commands
recorded for the first batch, with the corresponding program configurations.
The executable and test commands use six workers; the user waived load admission for
this session. No benchmark or timing comparison is run.

The [repository backlog validator](batch2-repository.log) and `git diff --check` also passed.

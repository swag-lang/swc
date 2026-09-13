# Eleventh static micro-pass batch

Build 538, source commit `fe3f20023`, based on the tenth validated batch in master.

| Change | Removed work | Preserved invariant |
| --- | --- | --- |
| InstructionCombine caches the global float-read width check | A whole-function scan per scalar sqrt/result-copy candidate | Separate B32/B64 answers refer to the same immutable IR/SSA snapshot; every first scan keeps its original early exits. Claims and rewrites still occur after all checks. |
| LoopUnroll shares fresh integer/float discovery when both are needed | A second operand walk | Renaming classification is read-only; integer-only cases retain their single-class scan and exact register names. |
| Register allocation compacts pending borrow restores in place | Repeated shifts after each expired request | Reload emission and survivor order are unchanged; emitters do not inspect or mutate the pending list. |
| Register allocation retains already ordered claim positions | Sorting lists produced by ascending instruction indices | Adjacent duplicate suppression makes each list strictly increasing from its first construction. |
| Failed interval allocation shares its concrete claims with the fallback | Rebuilding unchanged claim lists, plus an empty scan when no concrete register exists | Every failure precedes mutation of the indexed register effects/liveness. Each new pass run clears the lists before either allocator. |
| Straight-line range checks stop after their upper endpoint | Traversing the ignored suffix | The same instructions are checked through the inclusive bound, without computing a potentially overflowing upper bound plus one. |

Three added C++ tests cover repeated sqrt widths and late blocking float readers, three
borrowed registers whose middle restore expires first, and reuse of one allocator on changing
physical live ranges with exact alternating register choices. Existing unroll tests check
integer-only, float-renamable and preserved-name cases. Independent reviews cover every family.

All functional checks passed, each with exit code 0:

- [DevMode compiler build](batch11-build.log), MSBuild `/m:6 /p:SwcCompileJobs=6`.
- [C++ suite](batch11-cpp.log): 733 passed.
- [Native devmode](batch11-native-devmode.log): 3,131 passed; generated executable passed.
- [Native release](batch11-native-release.log): 3,131 passed; generated executable passed.

Commands use the checkout-local `tools/unittests.swgs dm` syntax recorded in the main report,
with six workers and the user's load-admission waiver. `git diff --check` passed.
No backlog metadata changed, so its standalone validator was not repeated.
No benchmark execution or performance comparison belongs to this batch.

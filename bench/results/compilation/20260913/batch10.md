# Tenth static micro-pass batch

Build 537, source commit `3db0d56fc`, based on the ninth validated batch in master.

| Change | Removed work | Preserved invariant |
| --- | --- | --- |
| SSA ends collection when there are no virtual definitions | Tracked-use collection, block construction, dominance, phi and rename work | No tracked SSA value or phi can exist. Instruction-local use/def data remains available, including across rebuilds. |
| SSA counts direct uses immediately when no phi exists | Traversal scratch, visit stamps and graph walking | Every use is an instruction use; the existing cap and invalid-value behavior remain intact. |
| SSA constructs instruction-to-block mapping while finding block ends, and predecessors alongside successors | Two separate mapping/edge walks and successor duplicate searches | The same leaders delimit each block; CFG targets are unique and multiple targets are distinct block leaders. Predecessors remain in source order. |
| SSA uses freshly constructed block defaults and removes three unread owner pointers | A redundant dominator reset walk and unused pointer storage/writes | Blocks are recreated before the single dominator computation; only the retained storage pointer has readers. |
| Legalize and vector construction discover fresh integer and float registers together | A second full operand walk when both register classes are needed | Integer hints, per-class maxima and saturation match the existing single-class helpers at the same original snapshot. Single-class scans remain available. |
| MemToReg assigns each slot's virtual register directly during rewriting | An allocation walk and an offset-to-register hash table | Promotion offsets are unique and no intervening action allocates another register, so names and rewrite order stay identical. |
| SLP bounds touched roots to its two-root rule | A per-plan hash set and insertion of roots beyond the rejection threshold | Membership is the same; the only later traversal computes symmetric stack/parameter flags. |

Six added C++ tests cover repeated SSA rebuilds with only physical definitions, capped direct
uses after a phi-bearing build, distinct adjacent indirect targets, fresh-index limits and
hints, mixed integer/float promoted slots, and the stack-plus-parameter root limit.
Independent reviews cover each family and the block ordering assumptions.

All functional checks passed, each with exit code 0:

- [DevMode compiler build](batch10-build.log), MSBuild `/m:6 /p:SwcCompileJobs=6`.
- [C++ suite](batch10-cpp.log): 730 passed.
- [Native devmode](batch10-native-devmode.log): 3,131 passed; generated executable passed.
- [Native release](batch10-native-release.log): 3,131 passed; generated executable passed.

Commands use the checkout-local `tools/unittests.swgs dm` syntax recorded in the main report,
with six workers and the user's load-admission waiver.
No benchmark execution or performance comparison belongs to this batch.

The [repository backlog validator](batch10-repository.log) and `git diff --check` passed.

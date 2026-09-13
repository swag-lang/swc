# Static micro-pass batch 20: Reject ineligible headers and multipliers earlier

Build 550, source commit `e63e47db7`.
All checks passed with exit code 0:

- [DevMode build 550](batch20-build.log), MSBuild `/m:6 /p:SwcCompileJobs=6`.
- [C++ suite](batch20-cpp.log): 763 passed.
- [Native devmode](batch20-native-devmode.log): 3,131 passed; generated executable passed.
- [Native release](batch20-native-release.log): 3,131 passed; generated executable passed.

The checkout-local commands retain six workers and the user's load-admission waiver.
`git diff --check` passed. No backlog metadata changed in this batch.

PostRALoopRotate checks for exactly one incoming jump before scanning the header's
test run and probing its relocation set. The incoming-jump index is immutable during
recognition, and the skipped scan has no effects beyond local variables. Accepted
headers retain the same scan, budgets, back-edge checks and rotation order.

StrengthReduction skips the flags scan for multiplications whose immediate is neither
zero, one, nor a power of two admissible for the operand width. All three reduction
helpers would otherwise refuse without effects. The prior unsigned-to-signed rewrite
and its stricter flags policy remain before this guard, including its `passChanged`
update. Admitted powers of two repeat a cheap eligibility check in the existing helper;
no measured net gain is claimed.

Existing tests cover independent rotating headers, multiple incoming jumps and a
conditional back edge, plus zero/one/non-power-of-two/power-of-two multipliers and both
flags policies. No additional test duplicates this guard rearrangement. Both changes
received independent review. No benchmark execution or timing comparison was run.

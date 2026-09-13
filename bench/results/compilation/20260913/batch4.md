# Fourth static micro-pass batch

Build 531, source commit `b7dfd435e`, based on the third validated batch in master.

`convertBranchesToConditionalMoves` now records whether any accepted conversion needs
an immediate materialization. When every accepted conversion is a register copy, it
skips the whole-function fresh-register scan. For mixed plans the scan still sees the
entire original instruction stream before any insertion or deletion, so register names
and conversion order remain identical. Rejected immediate candidates do not request
scratch registers.

One added C++ test covers both copy-only and mixed plans, an earlier rejected 8-bit
immediate candidate, and a high register at the end of the listing. Independent review
confirmed that only `fromImm` conversions consume the counter.

All functional checks passed; each command exited with code 0:

- [DevMode build](batch4-build.log), MSBuild `/m:6 /p:SwcCompileJobs=6`.
- [C++ suite](batch4-cpp.log): 701 passed, including the new branch-conversion test.
- [Native devmode](batch4-native-devmode.log): 3,131 passed and generated executable passed.
- [Native release](batch4-native-release.log): 3,131 passed and generated executable passed.

Commands are the same checkout-local `tools/unittests.swgs dm` commands recorded for
the first batch, with six workers and the user's load-admission waiver. No performance measurement is
part of this batch.

The [repository backlog validator](batch4-repository.log) and `git diff --check` passed.
Only the canonical `bin/unittests/.output` was found under test sources.

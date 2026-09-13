# Static micro-pass batch 15: Reused constants and omitted restore bookkeeping

Build 545, source commit `e848bb38a`.
All checks passed with exit code 0:

- [DevMode build 545](batch15-build.log), MSBuild `/m:6 /p:SwcCompileJobs=6`.
- [C++ suite](batch15-cpp.log): 754 passed, including three added tests.
- [Native devmode](batch15-native-devmode.log): 3,131 passed; generated executable passed.
- [Native release](batch15-native-release.log): 3,131 passed; generated executable passed.

The checkout-local tool commands retain six workers and the user's load-admission waiver.
`git diff --check` passed. No backlog metadata changed.

Constant folding reuses the SSA result already inferred for register-immediate operations,
removing a reaching-definition lookup and a second arithmetic evaluation. The destination's
SSA definition is unchanged before its rewrite; original operation width is retained, and CPU
flags are still checked against the current instruction stream. The new test covers four
widths, live/dead flags, division by zero and its unknown dependent.

SSA no longer reserves or records scope restores when the current block contains every
instruction remaining in the rename walk. Nonempty blocks partition that walk, so no child,
sibling or later root can follow it. Value creation, timelines and phi-input assignment remain
unchanged, including backedges. This avoids reserve/allocation and restore-point records.
The new test covers 16 registers, repeated writes, both a single block and a final self-loop with phis,
and two rebuilds of the same SSA object.

Stack-adjustment normalization visits returns directly after inserting its entry adjustment,
avoiding a temporary return-reference vector. Its iterator retains storage plus the current
reference; inserting before a return leaves its successor unchanged. Entry and exit insertion
order, including instruction provenance, remains unchanged. A new two-exit test checks exact
return references and restored stack amounts.

Independent cross-review covers all three changes.

No benchmark execution or performance comparison belongs to this batch.

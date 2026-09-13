# Static micro-pass batch 17: Reused integer results and SLP permutation roots

Build 547, source commit `a79f1c3d8`.
All checks passed with exit code 0:

- [DevMode build 547](batch17-build.log), MSBuild `/m:6 /p:SwcCompileJobs=6`.
- [C++ suite](batch17-cpp.log): 759 passed, including two added tests.
- [Native devmode](batch17-native-devmode.log): 3,131 passed; generated executable passed.
- [Native release](batch17-native-release.log): 3,131 passed; generated executable passed.

The checkout-local tool commands retain six workers and the user's load-admission waiver.
`git diff --check` passed. No backlog metadata changed.

Integer register-register folding reuses the result already inferred for its SSA definition,
removing two reaching-value queries and a second arithmetic evaluation. The separate float
conversion branch, the stricter integer-source guard, the original operation width and the
dynamic CPU-flag check remain intact. The new test covers four widths, distinct and aliased
operands, division by zero and an unknown right operand; existing cases protect live flags
and unknown left operands.

SLP retains only the first materialized tuple for each sorted set of four value IDs, including
multiplicity. That first tuple can provide every permutation in its class, so later tuples
in the previous vector were never consulted. Its exact source register and first-matching
lane selection are retained; tuple-register storage, ordering and instruction budgets are
unchanged. A new three-permutation test checks both shuffle controls and their shared source.

The orphaned MicroUseDefMap class and its project entries are removed. No live source referenced
it beyond an always-null MicroPassContext member, a conditional invalidation and two resets.
Removing that unused connection reduces context storage and eliminates those pass-manager
checks; shared SSA construction and invalidation are unchanged. Whole-repository reference
search and independent review found no remaining active consumer or special initializer.

Independent cross-review covers all changes. No benchmark execution or performance comparison
belongs to this batch.

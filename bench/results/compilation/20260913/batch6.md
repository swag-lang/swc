# Sixth static micro-pass batch

Build 533, source commit `891b51e52`, based on the fifth validated batch in master.

| Change | Removed work | Preserved invariant |
| --- | --- | --- |
| SSA phi placement skips definition blocks with no dominance frontier | Collecting definitions and processing worklist seeds that cannot produce a phi | Empty-frontier blocks performed no propagation. Terminal phis are still created in the same order, but need no worklist entry. |
| Stack adjustment normalization keeps original instruction references and depths in a contiguous vector | A hash-table node per instruction, repeated lookups during validation/application, and repeated list traversal setup | Every original instruction remains alive until application ends; inserted compensation instructions remain outside the original sequence. |
| Stack analysis records the minimum call depth during its initial scan | A separate whole-function call-depth scan | Every observed depth is at most the final frame size. A smaller minimum identifies exactly the same rejected functions; the no-call sentinel also handles a maximal frame. |
| Instruction combination starts local scans directly at live anchors | Six searches from the beginning of the instruction stream | The storage validates live references before iterator construction; successor order and the original window limits are unchanged. |
| Strength reduction reuses a successful strict flags proof | A second scan of the same unchanged suffix | Finding a flags definition before any use or boundary also satisfies the existing relaxed flags-dead rule. |
| SLP rejects insufficient stores or unresolved memory accesses after its initial scan | Candidate-map construction and location scans for blocks already known to be ineligible | The complete initial scan still assigns root identities used by following blocks. At least four stores are required for four vector lanes. |

Seven added C++ tests cover nested phi propagation, recycled instruction references and adjacent
SP copies, maximum stack depth with and without calls, local window boundaries, both flags
policies, and rejected SLP blocks followed by a vectorizable block. Independent reviews covered
all changed families.

All functional checks passed, each with exit code 0:

- [DevMode compiler build](batch6-build.log), MSBuild `/m:6 /p:SwcCompileJobs=6`.
- [C++ suite](batch6-cpp.log): 712 passed.
- [Native devmode](batch6-native-devmode.log): 3,131 passed; generated executable passed.
- [Native release](batch6-native-release.log): 3,131 passed; generated executable passed.

Commands use the same checkout-local `tools/unittests.swgs dm` syntax recorded in the main
report, with six workers and the user's load-admission waiver. No benchmark execution or
performance comparison belongs to this batch.

The [repository backlog validator](batch6-repository.log) and `git diff --check` passed.

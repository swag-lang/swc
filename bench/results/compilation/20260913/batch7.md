# Seventh static micro-pass batch

Build 534, source commit `4b3b3521c`, based on the sixth validated batch in master.

| Change | Removed work | Preserved invariant |
| --- | --- | --- |
| Relocation pruning removes invalid and dead references in one stable pass | A preliminary relocation scan and writes to records immediately erased | Storage rejects invalid, out-of-range and dead references. Survivor order and the changed result remain identical; quarantined slots are released afterward even when no relocation was removed. |
| Register allocation skips unused hint selection | Scanning every interval for a hint when no free candidate exists | The hint is consumed only in the free-register branch. |
| Allocation elections share one inline scratch buffer | Two heap-backed temporary arrays | The free and blocked phases overwrite the entire array before use, with no later reader of the preceding phase. Pools larger than inline capacity retain the existing dynamic fallback. |
| Instruction combination starts three more local scans at live anchors | Three prefix searches | Missing references, successor order, window limits and flag barriers are unchanged. |
| Store-to-load forwarding delays its relocation lookup table | Table construction when the scan never reads through RIP | Before the first RIP load the scan cannot invalidate a relocation. The first missing relocation still initializes the complete original snapshot. |
| Vector-loop promotion rejects a third alias root immediately | Growing and repeatedly searching an already disqualifying root list | The accepted set is still limited to the same allowed pair; rejected plans have no mutation. |
| Loop unrolling scans fresh floating-point registers only when needed | A whole-function scan when no surviving renaming candidate is floating-point | Eligibility is recorded during the existing final filter, before any mutation; every emitted register name remains unchanged. |

Four added C++ tests cover stable relocation pruning and slot recycling, lazy RIP lookup with
subsequent invalidations, the alias-root limit, and exact integer/float names with preserved
copy candidates. Existing allocation tests cover hints and both election paths. Independent
reviews found no remaining correctness concern.

All functional checks passed, each with exit code 0:

- [DevMode compiler build](batch7-build.log), MSBuild `/m:6 /p:SwcCompileJobs=6`.
- [C++ suite](batch7-cpp.log): 716 passed.
- [Native devmode](batch7-native-devmode.log): 3,131 passed; generated executable passed.
- [Native release](batch7-native-release.log): 3,131 passed; generated executable passed.

Commands use the same checkout-local `tools/unittests.swgs dm` syntax recorded in the main
report, with six workers and the user's load-admission waiver. `git diff --check` passed.
No benchmark execution or performance comparison belongs to this batch.

# Fifth static micro-pass batch

Build 532, source commit `8ebce8ced`, based on the fourth validated batch in master.

| Change | Removed work | Preserved invariant |
| --- | --- | --- |
| SSA resets bookkeeping during live instruction collection | A separate scan over every allocated instruction slot, including deleted slots, and a duplicate definition-list clear during renaming | Public queries exclude deleted slots through the slot/order map; recycled slots reset before use and still validate their cached opcode and operands. |
| Value numbering delays frame-derived register classification until a relevant memory load | Whole-function fixed-point classification for functions without eligible non-relocated loads | Rewrites remain queued, so classification still observes every original instruction, including later definitions. |
| MemToReg checks escaped variable ranges once per slot | Repeated access-by-variable overlap and containment scans | All accesses share their starting offset; both rejection predicates are monotonic in the computed endpoint, whose maximum is already collected. |
| Prologue preparation stops after a valid first frame-pointer initialization | Scanning a suffix whose result was always ignored | Every earlier use or invalid definition still rejects the remapping. |
| Prologue remapping uses the existing used-register set | A redundant transient-register set, its allocations and lookups | Every selected replacement is immediately inserted into the used set in the original selection order. |
| Legalization checks destination equality before preservation analysis | Liveness queries whose result was unconditionally masked | A required register equal to the original destination never needs preserving under the existing rule. |

Four added C++ tests cover erased and recycled SSA slots across rebuilds, later frame-derived
register definitions, widest accesses beside escaped variables, and frame-pointer remapping
priority with distinct transient replacements. Three agents implemented separate pass families;
independent reviews found no remaining correctness concern.

All functional checks passed, each with exit code 0:

- [DevMode compiler build](batch5-build.log), MSBuild `/m:6 /p:SwcCompileJobs=6`.
- [C++ suite](batch5-cpp.log): 705 passed.
- [Native devmode](batch5-native-devmode.log): 3,131 passed; generated executable passed.
- [Native release](batch5-native-release.log): 3,131 passed; generated executable passed.

Commands use the same checkout-local `tools/unittests.swgs dm` syntax recorded in the main
report, with six workers and the user's load-admission waiver. No benchmark execution or
performance comparison belongs to this batch. PowerShell's stderr wrappers in the logs do not
indicate command failure.

The [repository backlog validator](batch5-repository.log) and `git diff --check` passed.

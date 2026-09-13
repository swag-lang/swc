# Ninth static micro-pass batch

Build 536, source commit `dbcd94b66`, based on the eighth validated batch in master.

| Change | Removed work | Preserved invariant |
| --- | --- | --- |
| CFG constructs predecessors alongside successors | A third walk over all instructions and edges | Sources are visited in order; target validation, successor deduplication, predecessor order and backward-edge detection remain identical. |
| Store-to-load forwarding compacts invalid cache entries once | Repeated shifts of surviving entries after each removal | Both predicates are unchanged and survivors retain producer order. |
| Loop unrolling removes outside-read candidates directly | An outside-read hash set and a subsequent membership filter | The prefix and suffix erase the same candidates; no later outside read can restore a rejected candidate. Register naming still follows instruction order. |
| Prolog analysis records first physical-register touches while collecting uses | Repeated instruction scans for persistent-register remapping candidates | Uses win over definitions within an instruction; ABI choice order and the out-of-mask fallback remain intact. |
| Stack-release recognition skips the already validated run | Rewalking adjacent stack additions and Nops | The following Ret is still visited and closes the entry prolog region. |
| Register allocation stops an infeasible eviction probe immediately | Remaining active and inactive owner checks once an unsplittable owner was found | Feasibility only changes from true to false and all skipped probes are read-only. |

Five added C++ tests cover CFG rebuilds/indirect duplicates/backedges, forwarding-cache
survivors after multiple removals, outside and carried loop values, register first-touch
read/write ordering, and long stack-release runs followed by an entry boundary.

All functional checks passed, each with exit code 0:

- [DevMode compiler build](batch9-build.log), MSBuild `/m:6 /p:SwcCompileJobs=6`.
- [C++ suite](batch9-cpp.log): 724 passed.
- [Native devmode](batch9-native-devmode.log): 3,131 passed; generated executable passed.
- [Native release](batch9-native-release.log): 3,131 passed; generated executable passed.

Commands use the checkout-local `tools/unittests.swgs dm` syntax recorded in the main report,
with six workers and the user's load-admission waiver. `git diff --check` passed.
No backlog metadata changed, so its standalone validator was not repeated.
No benchmark execution or performance comparison belongs to this batch.

# Eighth static micro-pass batch

Build 535, source commit `bbe6d36bd`, based on the seventh validated batch in master.

| Change | Removed work | Preserved invariant |
| --- | --- | --- |
| Legalization removes an ignored preliminary conformance scan | One encoder query per instruction before the real legalization walk | Every existing encoder implementation only fills the local issue result; the discarded queries did not prepare any state. |
| Legalization discovers fresh virtual registers only at its first issue | Two full register scans for already conforming functions | Both counters are initialized from the complete original stream before any rewrite, and then persist through all subsequent issues. |
| SSA saves each register's block-entry value once per block | Repeated restore records and writes for subsequent definitions of the same register | All definitions precede dominator children. Intermediate restores share a rename position, so only the original entry value can be observed by later blocks. The reserve hint is capped by the number of tracked registers. |
| Pre-RA peepholes recognize a compatible pair before scanning flags | Suffix scans for pairs that cannot be rewritten | Both builders modify only a local action. Flags are still checked before claiming or changing an instruction. |
| SLP stops store checks at the packed-load insertion point | Traversing later stores for every packed load, and a redundant deletion-set lookup | Stores are in instruction order, and no store before the first deleted position belongs to the deleted set. |

Three added C++ tests cover late mixed integer/float legalization issues with exact scratch
names, SSA restoration through descendants/siblings/phis/disconnected roots, and overlapping
stores before or after SLP's load insertion. Existing pre-RA tests cover both pair rewrites with
live and dead flags. Independent reviews covered every changed family.

All functional checks passed, each with exit code 0:

- [DevMode compiler build](batch8-build.log), MSBuild `/m:6 /p:SwcCompileJobs=6`.
- [C++ suite](batch8-cpp.log): 719 passed.
- [Native devmode](batch8-native-devmode.log): 3,131 passed; generated executable passed.
- [Native release](batch8-native-release.log): 3,131 passed; generated executable passed.

Commands use the same checkout-local `tools/unittests.swgs dm` syntax recorded in the main
report, with six workers and the user's load-admission waiver. No benchmark execution or
performance comparison belongs to this batch.

The [repository backlog validator](batch8-repository.log) and `git diff --check` passed.

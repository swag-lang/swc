# Twelfth static micro-pass batch

Build 541, source commits `e65ffe90c`, `f306e9b92` and `8b4f6f18f`, based on the eleventh validated batch in master.

| Change | Removed work | Preserved invariant |
| --- | --- | --- |
| SSA value propagation finishes after its first sweep without phis | A redundant fixed-point confirmation sweep in constants, copies and branch simplification | Values are created in dominator order; each instruction's inputs precede its definitions. Without phis every dependency was already considered. Phi-bearing graphs retain their fixed point. |
| Copy elimination skips its phi fallback when no phi exists | A complete value scan that could never add a canonical value | Only unresolved phis can seed this fallback. |
| DCE returns when SSA contains no values | Usage preparation and an instruction-elimination walk | Every removable instruction must define a virtual value. |
| LICM indexes relocation chains by original instruction | A complete relocation scan for each relocated clone | The compact index retains every duplicate in original order. Claimed instructions appear in at most one hoist plan, and the relocation array stays fixed until retargeting completes. |
| Value numbering collects relocations at its first relevant candidate | Eager table construction for functions with no relevant memory/address candidate | Both lookup sites observe the same immutable relocation snapshot; later duplicate entries still win. |
| Value numbering moves completed keys into buckets | An allocation and copy for keys exceeding inline storage | The key has no remaining reader after insertion; hashing and equality use the same words. |

LICM's index uses one link per relocation, trading this linear scratch storage for removal
of repeated full-list retargeting. No generated-code optimization rule or iteration budget changes.

Five added C++ tests cover propagation with physical order differing from dominance and a
separate root, DCE on physical-only definitions, duplicate/interleaved relocations across hoisted
and retained instructions, and both lazy value-numbering lookup paths with last-entry precedence.
The dominance oracle now also runs its every-entry/every-node checks without the backedge,
covering forward-only graphs for subsequent optimizations. Independent reviews cover all families.

The initial build 539 C++ run stopped on a missing relocation kind in the new LICM
fixture ([initial build](batch12-build-initial.log), [assertion log](batch12-cpp-initial.log)).
After initializing that kind, build 540 reached the pipeline verifier, which rejected
intentionally synthetic relocation metadata in the two collector fixtures
([build](batch12-build-fixture-kind.log), [verification log](batch12-cpp-fixture-boundary.log)).
Both fixtures now invoke their pass directly with an explicit context; their data and
expectations remain intact. Production verification and optimizer assertions are unchanged.
Neither failed run launched native tests.

All final checks passed with exit code 0:

- [DevMode build 541](batch12-build.log), MSBuild `/m:6 /p:SwcCompileJobs=6`.
- [C++ suite](batch12-cpp.log): 738 passed.
- [Native devmode](batch12-native-devmode.log): 3,131 passed; generated executable passed.
- [Native release](batch12-native-release.log): 3,131 passed; generated executable passed.

Commands retain the six-worker validation caps and the user's load-admission waiver.
`git diff --check` passed. No backlog metadata changed.
No benchmark execution or performance comparison belongs to this batch.

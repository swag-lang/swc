# Static micro-pass batch 23: Dominance scratch, loop indices and vector claims

Build 553, source commit `ed84fffb0`.
All checks passed with exit code 0:

- [DevMode build 553](batch23-build.log), MSBuild `/m:6 /p:SwcCompileJobs=6`.
- [C++ suite](batch23-cpp.log): 768 passed, including two added tests.
- [Native devmode](batch23-native-devmode.log): 3,131 passed; generated executable passed.
- [Native release](batch23-native-release.log): 3,131 passed; generated executable passed.

SSA observes joins while installing immediate dominators and their child lists. A graph
without a block having two predecessors cannot contribute to the existing frontier walk,
so it skips that walk and its workspace. The dominator tree and all roots are still built.
This adds one join predicate per block to the existing tree walk. When joins do exist,
frontier stamps reuse the immediate-dominator scratch array after every dominator has
been copied onto its block; subsequent traversal reads only the block fields. This avoids
another array allocation and four bytes of peak scratch payload per block. A new test
checks sibling and disconnected-root scopes in a fork with separate exits; existing joins,
loops and rebuild tests cover the unchanged frontier construction.

InductionVariable and PostRALoopHoist remove their instruction-reference-to-ordinal maps.
The CFG snapshot follows the live instruction listing, so a preheader's predecessor is
`header - 1`, and the operation adjacent to an induction copy is `i + 1`. Bounds and exact
reference checks remain explicit. Induction ends the round after a mutation; post-RA
hoisting defers insertions and erasures until all loops are analyzed. Its intermediate
register redirections preserve listing order. The next round rebuilds the snapshot.
An unused map parameter is removed too. A new induction test distinguishes live adjacency
across erased storage slots from a retained Nop between the copy and operation; it checks
the selected carrier and which instructions disappear. Existing post-RA tests exercise
subsequent rounds after mutation.

BuildVector inserts claims directly after its original claim and relocation guards.
The collected stores are distinct and precede the load. The intervening plan construction
changes only its steps and register counters; claimAll had no additional side effects.
Repeated membership probes and unreachable refusal branches disappear, while initial
rejections, rollback of failed plans and load-then-store claim order remain unchanged.
Existing native vector-literal tests cover repeated and distinct lanes, zeros, partial
fills and additional readers.

All families received independent review. The checkout-local DevMode compiler and six
workers are retained under the user's load-admission waiver. Native devmode and release
cover the guarded pipeline and vector construction paths. `git diff --check` passed.
No backlog metadata changed, benchmark executed, or timing comparison run.

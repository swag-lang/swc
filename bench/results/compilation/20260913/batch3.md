# Third static micro-pass batch

Build 529, source commit `07fab66e9`, based on the second validated batch in master.
This is a functional-validation batch; performance measurement remains deferred.

| Change | Work removed | Preserved contract |
| --- | --- | --- |
| ValueNumbering builds dominance at its first fully matching candidate | CFG DFS, immediate dominators, and subtree intervals when no expression needs comparison | Same immutable CFG, candidate order, keys, memory epochs, and deferred rewrites. |
| SSA reports whether dominator construction produced any frontier | Definition-block collection and phi worklists when phi placement has no possible destination | Dominator construction and SSA renaming still run; build resets prior phi state. |
| Legalize answers ABI-register liveness together | Repeating the same prefix search and suffix use/def collection for each ABI register | Barriers are checked before touches, uses before defs, ABI insertion order preserved, original fallback for registers outside the mask. |
| Legalize starts a single-register probe at the following instruction | Scanning from the beginning to find the starting instruction | Existing reference membership and missing-reference fallback are preserved. |

Four added C++ tests cover sibling expressions and dominance at a join, SSA rebuilding
from several frontier-free blocks to a new disconnected join, first register touches,
implicit register uses, and label/jump/call barriers. Cross-review found no correctness
issue; the SSA test was refined to exercise multiple actual SSA blocks.

All functional validation passed; each command exited with code 0:

- [DevMode build](batch3-build.log), MSBuild `/m:6 /p:SwcCompileJobs=6`.
- [C++ suite](batch3-cpp.log): 700 passed, including all four added tests.
- [Native devmode](batch3-native-devmode.log): 3,131 passed and generated executable passed.
- [Native release](batch3-native-release.log): 3,131 passed and generated executable passed.

The checkout-local `tools/unittests.swgs dm` commands are the same as in the first batch. All compiler commands use six
workers under the user's load-admission waiver; no benchmark or timing comparison runs.

The [repository backlog validator](batch3-repository.log) and `git diff --check` passed.

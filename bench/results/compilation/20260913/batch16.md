# Static micro-pass batch 16: Shared copy queries and direct epilogue traversal

Build 546, source commit `bfce5aebc`.
All checks passed with exit code 0:

- [DevMode build 546](batch16-build.log), MSBuild `/m:6 /p:SwcCompileJobs=6`.
- [C++ suite](batch16-cpp.log): 757 passed, including three added tests.
- [Native devmode](batch16-native-devmode.log): 3,131 passed; generated executable passed.
- [Native release](batch16-native-release.log): 3,131 passed; generated executable passed.

The checkout-local tool commands retain six workers and the user's load-admission waiver.
`git diff --check` passed. No backlog metadata changed.

Epilogue sanitization finds the first instruction in a return suffix once, then follows
instruction links instead of rebuilding and reversing a reference vector after every merge.
It restarts at that same first reference after each successful merge, retaining retries of
earlier rejected pairs. The first reference cannot be the erased second member of a pair;
surviving opcodes remain epilogue instructions. Returns are visited directly because only
preceding instructions are erased. A new test checks multiple returns, an empty suffix,
separate adjustment chains and overflow rejection followed by a later successful merge.

Copy elimination reuses its source reaching definition when the inferred canonical register
is that same source, avoiding a second identical timeline lookup. The source/root value-ID
comparison and all width and zero-high-bit guards are retained.

Early-return matching scans each tail instruction once when checking whether it overwrites
a compare input, rather than collecting its definitions separately for each input. This
preserves the same intersection/rejection predicate. A new test checks an unrelated write
and writes to each of the two comparison inputs.

Loop unrolling builds its relocation indexes at the first structurally eligible backward
jump, immediately before their first possible lookup. Empty indexes are cached explicitly.
Candidate failures do not mutate the snapshot; successful unrolling ends the sweep before
rebuilding. A new test rejects an initial loop with an external entry, then unrolls a following
loop and checks the exact order and targets of three valid RIP-relative relocations.

Independent cross-review covers all four changes.

No benchmark execution or performance comparison belongs to this batch.

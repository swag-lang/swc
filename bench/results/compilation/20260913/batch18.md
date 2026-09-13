# Static micro-pass batch 18: Extension results, tuple keys and coalescing setup

Build 548, source commit `cf49d0f80`.
All checks passed with exit code 0:

- [DevMode build 548](batch18-build.log), MSBuild `/m:6 /p:SwcCompileJobs=6`.
- [C++ suite](batch18-cpp.log): 760 passed, including one added test.
- [Native devmode](batch18-native-devmode.log): 3,131 passed; generated executable passed.
- [Native release](batch18-native-release.log): 3,131 passed; generated executable passed.

The checkout-local tool commands retain six workers and the user's load-admission waiver.
`git diff --check` passed. No backlog metadata changed.

Sign and zero extensions reuse the result already inferred for their SSA definition, avoiding
a source-reaching lookup and repeated extension arithmetic. Opcode and virtual-integer guards,
destination width and flag preservation remain unchanged. One added C++ test exercises six
width/value cases, signed and unsigned extension, distinct/aliased/unknown sources, and live flags.

SLP passes the sorted tuple key already computed in TreeBuilder to its registration sites.
The key is a local value that survives recursion; load canonicalization still computes its own
independent key. A permutation already found its class, so it registers only its new tuple's
register and avoids reinserting the existing class. Plan order, registers and budgets are intact.
Existing SLP tests, including the exact permutation oracle added in batch 17, cover these paths.

Register-allocation coalescing locates its current copy directly and traverses the suffix,
avoiding a complete prefix search per copy. The reference guard precedes next-link access,
and checks remain use-before-def, then barrier/return. Its instruction-effect vector is no
longer initialized before coalescing only to be cleared and rebuilt afterward: all coalescing
helpers use local effects, and every cached consumer runs after final preparation. Existing
coalescing, barrier and same-object allocator tests cover those invariants.

Independent cross-review covers all three families. No benchmark execution or performance
comparison belongs to this batch.

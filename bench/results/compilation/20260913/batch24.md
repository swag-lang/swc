# Static micro-pass batch 24: Liveness buffers and address roots

Build 554, source commit `8ccfd4f2c`.
All checks passed with exit code 0:

- [DevMode build 554](batch24-build.log), MSBuild `/m:6 /p:SwcCompileJobs=6`.
- [C++ suite](batch24-cpp.log): 770 passed, including two added tests.
- [Native devmode](batch24-native-devmode.log): 3,131 passed; generated executable passed.
- [Native release](batch24-native-release.log): 3,131 passed; generated executable passed.

Register allocation consumes its temporary live-out buffers in place to compute live-in.
Only live-in is published during the fixed point, so two additional buffers and their
whole-vector copies on every instruction visit were redundant. Successor unions, kill/gen
order, comparison and predecessor scheduling remain identical. Every later live-out reader
already rebuilds its scratch first. Existing tests cover more than 64 integer and floating
registers, calls, spills, loops, and reusing an allocator across different CFG shapes.

LoadFold resolves each original address root once, lazily, during its read-only reread
window. Candidate roots are still resolved at their own instruction references; memory
change checks retain their original endpoints. The eight-copy depth and 32-instruction
window are unchanged. A new direct pass test checks successive base and index mismatches,
root redefinitions and a final match through copies of the old address, with exact fold
and refusal outcomes.

A second new test protects LICM frame privacy through copy chains whose listing order is
opposite to execution order, including an escaping terminal copy. LICM production code
is unchanged in this batch. A proposed pending-list closure rewrite was excluded because
its staging allocations could add work to ordinary cases.

All changes received independent review. The checkout-local DevMode compiler and six
workers are retained under the user's load-admission waiver. Native devmode and release
exercise allocation in guarded code and the distinct inlining/vectorization pipeline.
`git diff --check` passed. No backlog metadata changed, benchmark executed, or timing
comparison run.

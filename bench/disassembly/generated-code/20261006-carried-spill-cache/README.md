# Carry private spills across branch arms and loop exits

After ordinary post-allocation hoisting and promotion, a call-free loop may retain a
private 64-bit integer spill home in a caller-saved XMM register unused in that loop
and dead at its preheader. Every matching read/write becomes a bank transfer. One
seed read precedes the header and one write-back precedes each distinct exit block.

The rule rejects shared exit entries, indexed/derived stack accesses, stack changes,
unknown-width stack accesses, overlapping or mixed-width slots, and source objects
outside the allocator's spill area. No additional ABI save is introduced. CFG and
physical liveness are refreshed between changed loops. A conditional preheader jump
that targets the next header is also rejected, because its taken edge skips a seed.

The retained H.264 comparison contains the same 334 function bodies as the preceding
loop-load-forward lot. Total Micro instructions change from 43,950 to 43,957; memory
operations from 9,995 to 9,959; explicit RSP accesses from 2,249 to 2,213. Pushes stay
at 1,002. The five residualCabac instances lose 13 memory operations in total, with
unchanged instruction count. Some interpolation loops add seed/write-back instructions
outside their bodies; the per-function tradeoffs are in structural-evidence.json.
The diff pairs template instances by closest instruction body and normalizes relocation
addresses. Label identifiers can change between compilations. Intervening master updates
included SSA analysis reuse, semantic operand handling and native image construction;
this is structural evidence, not an isolated timing comparison.

Validation: checkout-local Release compiler, Release programs; 282 native optimizer
tests (JIT and native), 23 H.264 tests and nine HEVC decoder tests pass. The new source
case covers zero iterations, high integer pressure, changing arms and early exits
against an unoptimized array implementation. The C++ fixture covers two arms/two exits,
overlapping writes, shared exits and a jumping preheader; it was not executed because
C++ unit tests are excluded from the Release executable. No runtime speedup is claimed.

The final source also incorporates `cac30af45`; the Release compiler was rebuilt
and the new pressure/exit test rerun after that branch-analysis integration.

# Keep mutable private spill caches coherent across calls

Private 64-bit integer homes in loops with conditional calls can now use the
existing free-XMM cache even when written. Each original store remains and also
updates the cache; reads use it, and clobbering calls restore it on their in-loop
fallthrough. Memory is therefore current on every exit, including shared exits,
without extra flushing. The reuse check counts removed reads rather than stores.
Call-free writable homes retain their exclusive-exit write-back behavior.

Compared with the preceding read-only cache, Inflate.parseBlock changes from
512 instructions / 148 memory operations / 59 explicit RSP accesses to 518 / 145 /
56. Its literal-path latch now has zero frame accesses: the final mutable cursor
reload becomes a GP-from-XMM transfer. Refill stores remain, with cache updates;
one redundant restoration disappears when the call is followed by an overwrite.
The other four printed Inflate bodies retain their counts. This closes the
remaining literal-path cursor issue in compiler.optimization.006.

Across the same 334 H.264 bodies, counts change from 44,008 / 9,943 / 2,192 to
44,014 / 9,940 / 2,189, with 1,002 pushes unchanged. Slice.predictIntraPlane loses
two memory operations and Slice.parsePcm loses one, each gaining three register
instructions. Per-function evidence and the normalized Inflate diff are retained.
These are structural improvements; no elapsed-time speedup is claimed.

A Release compiler and Release programs pass all 3,634 native tests in JIT and
native execution, including the expected native recovery probes, 21 compression
tests and 23 H.264 tests. The native cold-call fixture now also varies mutable
carried values, early exits, post-loop uses, source mutation and floating call
results over 60 combinations. The C++ fixture records the corresponding cache
rewrite, but was not executed because internal C++ tests are excluded in Release.

A broader prototype attempted to omit stores through dead-exit proofs. It could
not cover the observed cursor's live exits and was removed before retention.
The retained extension adds no exit analysis or deferred memory state.

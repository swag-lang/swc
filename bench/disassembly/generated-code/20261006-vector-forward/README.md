# Forward packed stores into later loads

Batch 15, based on 3c3e5165c, Release compiler and programs. The ordinary
store/load cache now accepts the equivalent packed load/store operand layouts.
It retains exact base, displacement and width matching, relocation identity,
source/base redefinition invalidation, overlapping-write barriers and claims.

ChaCha's four state reloads after the packed round loop become register copies
and disappear during cleanup. One additional saved XMM register costs two
prologue/epilogue memory operations, so main changes from 425 instructions / 113
memory operations to 423 / 111 overall. The repeated output path loses all four
state reloads. Its four stores remain; proving them dead is separate work.

The 334-body H.264 panel stays at 44,015 instructions, 9,942 memory operations,
2,189 explicit RSP operands and 1,002 pushes. No runtime timing claim is made.
The user authorized retaining static savings on the occupied machine.

The 292 focused optimizer tests and 23 H.264 tests pass in Release JIT and
native execution. ChaCha, nbody and csvagg checksums match the baseline.
Nbody and csvagg retain their instruction and memory counts.
Ten internal forwarding variants cover scalar/vector interoperation, repeat
loads, overlapping writes, a second root, source redefinition, displacement
mismatch, disjoint stores and claimed producers. These C++ fixtures were added
but not executed by the Release-only compiler.

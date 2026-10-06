# Cache private spills in loops with shared exits

Batch 19, based on a172a3428. Release compiler and optimized programs.
Call-free loops may now cache mutable private 64-bit spill homes even when an
exit also has an outside predecessor. Keeping each existing memory store coherent
avoids an unconditional write-back on a path that skipped the loop. Write-only
homes are excluded from this mode because they have no read to replace.

| H.264 function | Instructions before / after | Memory operations before / after | RSP accesses before / after |
| --- | --- | --- | --- |
| halfHorizontalAvg | 183 / 183 | 40 / 37 | 3 / 0 |
| halfCenter | 190 / 190 | 22 / 19 | 7 / 4 |
| Slice.buildImplicitWeights | 118 / 118 | 19 / 16 | 11 / 8 |

The other 331 bodies retain their counts. The complete panel stays at 43,998
instructions while memory operations fall from 9,925 to 9,916 and explicit RSP
accesses from 2,191 to 2,182. Pushes remain 1,002. In each changed body the loop
carried integer value moves to a free caller-saved XMM register; later dead-store cleanup also
removes stores whose value is unobserved at exit. Csvagg's three bodies remain
969 instructions / 250 memory operations. No runtime timing claim is made.

Validation: 293 native optimizer tests and 23 H.264 tests pass in Release JIT
and native execution; the repository check also passes. Internal fixtures cover shared exits and reject a write-only home in
this mode; those C++ fixtures are not executed by the Release compiler.

# Promote known locals reached through the stack pointer

Batch 16, based on 009a4294e and validated with master 583f53466. Release
compiler and programs. MemToReg distinguishes known local extents from outgoing
stack arguments. Direct SP accesses and addresses captured while SP is adjusted
use the displacement at the instruction; copied outgoing addresses retain their
origin. Existing escape, overlap, width and control-flow proofs still apply.

ChaCha keeps three more state chunks in XMM registers. Per encrypted block,
three copy stores, three round-entry loads and three round-exit stores disappear.
The fourth chunk remains in memory because a later scalar read selects lane 3.
Its frame allocation shrinks from 672 to 656 bytes. Main stays at 423 instructions
and drops from 111 to 109 memory operations; initialization changes offset part
of the repeated-path savings. This is static evidence, not a timing result.

Nbody, csvagg and all 334 H.264 bodies retain their instruction/memory counts.
The 292 optimizer and 23 H.264 tests pass in Release JIT and native execution.
Four internal fixture variants cover captured local addresses, their copies,
outgoing argument space and a range crossing a local's end. They were added but
are not executed by the Release compiler. Benchmark checksums are retained here.

The final integration also includes d2130cf66: two reviewed SemaEscape lookup
reuse changes, with no backend or test-input change. The retained generated-code
evidence and execution checks were produced with 583f53466 plus this batch.

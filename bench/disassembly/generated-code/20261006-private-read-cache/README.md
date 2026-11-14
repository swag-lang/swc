# Keep read-only private spills across conditional calls

A private 64-bit integer spill home that the loop never writes can be cached in
an unused caller-saved XMM register. Cache seeds execute on every outside entry,
including direct/conditional jumps; a register must be dead after every entry
predecessor, including the branch that does not enter. Calls retain their argument
and observed result registers. Only clobbered caches are restored after a call,
on its fallthrough edge inside the loop. No additional ABI save is introduced.

The loop must have a call-free route to its back edge. The candidate's textual
reads must outnumber its seeds plus call restorations. This bounds cases where
restoration would cost more memory operations than the cache removes. Writable
homes keep the existing call-free/exclusive-exit rules. Stack changes, derived
stack addresses, overlaps and unknown-width accesses remain disqualifying.
Read-only homes need no exit write-back, so shared exits are supported.

Inflate.parseBlock changes from 497 instructions / 154 memory operations / 65
explicit RSP accesses to 512 / 148 / 59. Three of the four frame reads at the
literal-path latch become GP-from-XMM transfers. One seed of each of three values
precedes entry; four conditional-call sites restore them. The mutable cursor
still loads from the frame. This moves memory work off the repeated literal path;
no elapsed-time improvement is claimed. The four other printed Inflate functions
retain their counts. The baseline is the retained SSA-dominance dump; intervening
master and partial-unroll updates are included in this structural comparison.

The same 334 H.264 functions change from 43,982 / 9,966 / 2,215 to
44,008 / 9,943 / 2,192; pushes remain 1,002. Additional entry/restore instructions
accompany 23 fewer memory operations. The nine changed function groups and their
tradeoffs are recorded in structural-evidence.json. An unrestricted first
prototype had grown H.264 by 126 instructions and 32 memory operations; its
insufficient-reuse cases were excluded before retention.

Validation uses a Release compiler and Release programs: 288 optimizer tests
pass in JIT and native execution, 21 core compression tests pass, and 23 H.264
tests pass. The new native source varies zero/short/long loops and call frequency,
checks source mutation against captured values, and uses a floating call result.
The C++ fixture adds conditional versus unavoidable calls and written-home
counterexamples, and updates the jumping-entry case; it was not executed because
C++ unit tests are excluded from Release. Csvagg and SHA-256 retain their function
counts and checksums (24828641 and 2503168387). No timing campaign was run.

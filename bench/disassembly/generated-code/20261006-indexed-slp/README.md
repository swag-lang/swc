# Indexed read-modify-write SLP

Batch 14, Release compiler and Release programs, baseline `16f870d0d`.
The candidate also includes concurrent master work through `31a091266`.
The user's session instructions accept structural savings without timing significance
on the occupied machine. These counts establish generated-code changes, not a measured
runtime speedup. SWC_BUILD_NUM stays 1173.

SLP now models contiguous indexed loads and read-modify-write stores, proves that the
base and index stay stable until every affected access, and preserves captured values
when a source register has multiple definitions. Overlapping roots, mixed-width writes,
live flags and sequential dependencies retain their scalar behavior. A shared frame
privacy analysis permits an unknown pointer beside local memory only when no frame
address can escape on a CFG path reaching the accesses. LICM keeps its early-out form.

ChaCha main changes from **446 instructions / 143 memory operations to 425 / 113**.
The three printed bodies total 493 / 175 before and 472 / 145 after. The 16-word
output update becomes four packed add/XOR/store groups. Four stores of the round
state and four reloads of that state remain: carrying the vectors directly into the
output calculation is still open in compiler.optimization.098. Explicit RSP operands
increase from 31 to 39 because packed local reads use RSP instead of the saved base;
that count alone is not a spill count. Prologue pushes remain nine across the panel.

The first prototype produced a wrong checksum: MemToReg ignored direct SP accesses
when a call elsewhere adjusted SP, promoted three state-copy destinations, and lost
their writes before the vector loop. The retained repair computes SP displacements
through CFG joins and backedges and includes those reads/writes in the same slot
analysis as the captured frame base. Unknown displacements stop promotion. The
reduced copied-state/variadic-call regression fails with the prototype and passes
with the repair, in both JIT and native execution using the Release test configuration.

The 334 H.264 bodies change from 44,014 / 9,940 to 44,015 / 9,942 instructions /
memory operations. addChromaResidual saves three of each. The required alias repair
adds four instructions and five memory operations across applyMotion,
deriveDirectTemporal, deriveDirectSpatial and parseSubMvs; these local costs are
reported rather than hidden in the aggregate. Nbody saves five instructions and
four memory operations (1,385 / 520 to 1,380 / 516); csvagg stays at 951 / 239.
ChaCha, nbody and csvagg checksums match their preserved baseline.

Validation: the four new focused Release tests pass; 3,638 native-suite tests pass
in JIT and native execution, including the suite's expected recovery probes; 21
compression and 23 H.264 tests pass. Five internal SLP variants cover dead flags,
index mutation, a second unknown pointer and overlapping byte writes. Their C++
fixtures are retained but were not executed by the Release-only compiler.

No timing campaign was run. Compiler time/memory tradeoffs were not measured.
The new CFG displacement analysis is lazy, only for direct SP accesses in functions
whose SP moves, and propagates each node from unvisited to known to unknown at most.

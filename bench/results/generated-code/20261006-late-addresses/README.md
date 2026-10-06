# Fold address bases after frame promotion and vectorization

A single-use 64-bit constant-offset address now folds into a memory operand during
pre-allocation scheduling. The rule handles indexed operands and ordinary field
accesses, including read/modify/write instructions. The memory access keeps its
position, width, flags, and volatile/atomic behavior. Displacements use unsigned
wrapping arithmetic and must fit a signed 32-bit encoded displacement.

Within a block, reuse the scheduler's source-stability proof. A candidate across
blocks builds SSA lazily and requires the same base value at the address definition
and the memory access. Multiple-use or multiply-defined address registers remain
unchanged. Relocations remain protected. Planned consumer rewrites prevent later
scheduling from restoring stale operands.

This stage preserves the array shape used by frame promotion and vectorization.
The earlier attempt recorded under compiler.optimization.036 folded before those
passes and substantially increased the predictor's memory traffic.

## Release code evidence

The baseline is the retained compiler from the legalization-reserve lot
(`097927c1d` plus `0b75a69cc` compiler changes). The candidate starts at `cd799b15d`.
The intervening merge changes CodeGen/TypeInfo accessors; compiler hashes are in
`structural-evidence.json`. No runtime speedup is inferred from static counts.

The same H.264 source cohort and command described in
[the preceding lot](../20261006-legalize-reserve/README.md) emits 334 functions:

| Count | Before | After | Difference |
| --- | ---: | ---: | ---: |
| Instructions, excluding labels | 44078 | 43950 | -128 |
| Memory operations, excluding address computations and push/pop | 10018 | 9995 | -23 |
| Explicit RSP memory operations | 2262 | 2249 | -13 |
| Pushes | 1013 | 1002 | -11 |

`intraPredict8x8` changes from 977 to 972 instructions, with 429 memory operations
on both sides. `residualCabac` loses 15 instructions across its five instances;
`addChromaResidual` loses 19 instructions and 11 memory operations. `parsePartitions`
gains three instructions and two memory operations, retained as a separate allocation
lead. Explicit RSP counts also change when an address becomes directly based on RSP;
they are not a complete or exclusive count of allocator spills.

## Validation

Release compiler build, 278 native optimizer tests including the new field/indexed
address and branch-reassignment fixture, and 23 H.264 tests through JIT and native.
The four unchanged benchmark programs additionally retain their baseline checksums
(recorded in `checksums.json`). Every compile/test command has fresh machine-load
admission and six workers; all compared programs use Release and rebuilt artifacts.

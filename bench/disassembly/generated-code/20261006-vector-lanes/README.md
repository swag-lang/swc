# Preserve packed locals with scalar lane reads

Batch 17, based on 81e616f2e. Release compiler and programs. Full-width vector
writes now share one promoted register with aligned 32/64-bit integer lane reads.
Each nonzero lane is shuffled at the read, after its reaching vector write.
Partial writes, misalignment, unsupported readers and alias barriers still block
promotion. Existing single-write splitting shares the same lane extraction.

| Consumer | Instructions before / after | Memory operations before / after |
| --- | --- | --- |
| ChaCha main | 423 / 421 | 109 / 105 |
| Nbody, four printed bodies | 1,380 / 1,372 | 516 / 507 |
| H.264 parseScalingMatrices | 339 / 322 | 118 / 101 |
| Csvagg, three printed bodies | 951 / 969 | 239 / 250 |

ChaCha's fourth state chunk loses its copy store, round-entry load, round-exit
store and final scalar load. One shuffle plus one register move replaces the
scalar read. All four packed chunks are now register-resident across the rounds;
no extra saved register is needed. This closes compiler.optimization.046/.098.

H.264's other 333 bodies retain their counts. parseScalingMatrices gains one
spill store/reload and 16 frame bytes while eliminating substantially more local
memory traffic; explicit RSP accesses are 38 / 40 and pushes remain seven.
The entire panel is 44,015 / 43,998 instructions and 9,942 / 9,925 memory operations.

Csvagg promotes a copied region string's pointer/length across data-generation
work, exposing longer GP lifetimes around the integer multiplications. Frame
allocation grows by 64 bytes and explicit RSP accesses by 14. The suffix beginning
at the first timing call, after data generation, retains 444 instructions and
151 memory operations. The allocation diff is retained and the remaining setup
cost belongs to compiler.optimization.035; the general promotion is retained.
No runtime timing claim is made.

Validation: 293 optimizer tests, 21 compression tests and 23 H.264 tests pass in
Release JIT and native execution. ChaCha, nbody and csvagg checksums match.
The new source regression covers repeated whole copies and 32/64-bit lane reads
with zero, one and multiple iterations. Internal fixtures cover repeated writes,
partial writes, misalignment and label-separated reads; these C++ fixtures were
not executed by the Release-only compiler.

# Sort and LZ77 generated-code work

The session targets the timed sort and LZ77 workloads without editing their sources,
inputs, checksums or timed boundaries. Baseline source was `71f642e258`; its Release
compiler and runtime were preserved outside the checkout. The first four batches
are integrated in `18e7b8a166`, including concurrent prompt 4 changes. The Release
compiler measured by the first campaign was built from that combined revision.

| Batch | Mechanism | Static evidence in the executed path | Correctness |
| --- | --- | --- | --- |
| `e35b5cb833` | Reuse the first scan's compared value across read-only control flow | One fewer reload per partition swap | 1,549 C++ tests, 4 Release JIT/native cases, all 12 checksums |
| `78eafb8a84` | Parallel shift/add for `x * (2^k + 1) + y` | Three hash stages: 12 to 6 modeled arithmetic dependency cycles; whole hash 12 to 15 instructions, with no extra memory or spill | 1,556 C++ tests, 3 Release JIT/native cases, all 12 checksums |
| `c68640e492` | Retain the second scan's value through an equivalent pointer copy | Partition swap falls from 4 to 2 memory operations overall: two stores, no reload | 1,556 C++ tests, 4 Release JIT/native cases, all 12 checksums |
| `ea56174785` | Root `[base + (induction - fixed)]` at `base - fixed` | Decompression 8 to 6 instructions per output byte, same 2 memory operations | 1,557 C++ tests, Release JIT/native replay across 42 overlapping and zero-length cases, all 12 checksums |

All native regression runs used the DevMode compiler, Release programs,
`--validate-micro`, and six compiler workers. Final native code was inspected.
The compiler version/build identity was not changed. Captures and output caches
were kept separate between compilers.

The scan read becomes a load and a register comparison. Each scan advance has
four encoded instructions instead of three, but LLVM-MCA 20.1.8's Meteor Lake
model gives both forms three uops and the same 110 cycles over 100 iterations.
This is a model, not a measured speedup. No frame growth, spills, added calls or
saved registers were introduced in qsort.

Two incidental loop rotations duplicate an entry test in the listing: LZ77's
untimed data-generation copy and `Allocator.releaseAll`. For k executed body trips,
the allocator's old shape has 11k + 3 instructions and the new one 10k + 3, with
the same k + 1 header loads. The additional textual memory operand is the duplicated
entry test. Allocation fast paths retain their work. Function and enclosing-loop
totals alone must not be read as dynamic costs.

The hash's single-block LLVM-MCA model changes from 21 to 15 cycles and reciprocal
throughput from 3.0 to 2.3. Inputs, shifts and intermediate arithmetic keep their
original widths; flags, shared products and independently live addends retain their
original code. No general power-of-two-minus-one rewrite was retained: a naked
shift/subtraction rewrite would lose an existing bounded-remainder proof.

Analysis cost: compared-load search is bounded to 96 instructions; candidate
reloads require bounded predecessor traversal and stable SSA addresses. The scan
value may be reused through one proved full-width base copy. Scaled-add matching
uses at most two product sides, one copy and the existing 32-instruction window.
Invariant-subtraction rooting reuses LICM's loop and dominance facts and checks
that the computation dominates every loop tail and exit.

## Measurements

Initial paired sort/LZ77/wordfreq measurements were noisy and stayed inside
unchanged A/A controls. They neither confirmed a speedup nor supplied a veto.
All paired samples are retained in `paired-initial.json`.

The full campaign of `18e7b8a166` agreed on every checksum across every runtime
and completed all fourteen allocator workloads. The harness rejected its timings:
the reference workload departed **67.4%** from a neighbouring probe around leven,
beyond the 40% limit. Compilation measurements without a confirming pair were
omitted individually. The complete unaltered record is
[20261020-072804.json](../../rejected/20261020-072804.json).

No new history entry or corrected execution index is derived from that rejected
campaign. The latest accepted campaign remains `20261019-181609`; all four batches
above are **landed, unconfirmed**. The preserved baseline Release SHA-256 is
`177851dd23113d633f92dc301bfda972d60ca7654a8bb4cba94d2832218a1ab7`;
the measured combined Release SHA-256 is
`6197fa1ff94beea91f152b043d2307c79b145c789dfd687b0d5ac9f43272e739`.
No session builds or tests overlapped the campaign.

The next candidate for constant unsigned division follows the even-divisor
pre-shift construction in [LLVM's DivisionByConstantInfo](https://llvm.org/doxygen/DivisionByConstantInfo_8cpp_source.html).
It is not part of the four-batch compiler above.

## Eligibility repairs after the first campaign

The comparison reload proof now rejects materialized labels on a traversed path,
and LICM rejects loops with a materialized body entry. Such an entry can bypass
the read or the new preheader even when ordinary CFG predecessors appear closed.
The all-path scan fixture also retains an atomic/volatile-load boundary.

Scaled-add reassociation now accepts only leaf addends through bounded copies
and extensions. A weighted accumulation such as `acc += byte * 33` must keep one
addition on the loop-carried accumulator path; the reassociated form would put two
there. Computed addends and partial definitions retain their original arithmetic.
The LZ77 hash's byte loads remain eligible.

All three new internal regression groups failed with the pre-repair implementation.
After repair, all 1,561 C++ tests passed. The complete optimizer source directory
passed 316 tests through JIT and 316 natively in DevMode with `--validate-micro`.
All twelve Release benchmark checksums and instruction/memory/call/loop counts
match the four-batch compiler after overloaded runtime bodies are paired.
These repairs therefore preserve the target changes reported above.

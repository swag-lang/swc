# Static assessment, 2026-11-14

These are estimates about the captured implementations, not measured winners. The archive
contains 288 checksum-validated references, including Swag, eleven other native/JIT toolchain
families and CPython bytecode. C++ has a complete optimization-level/ISA control: GCC and
Clang each at O2/O3, with default ISA and x86-64-v3. Rust, Zig, LDC and Odin also have explicit
v3 variants; Swift has a separately labelled Haswell variant. Missing Windows/MSVC/NativeAOT
and uncaptured interpreter implementations cannot be ranked.

## Candidates to test first

A slash means the static evidence does not resolve those candidates. Confidence concerns
this shortlist, not an assertion that the program is fastest. Inspect the exact port contracts
before attributing a difference to the backend. Most rows remain unresolved without execution.

| Task | Provisional candidate(s) | Confidence | Evidence and limit |
| --- | --- | --- | --- |
| wordfreq | Swag / Clang | Medium for hashing, low overall | Swag's four-byte FNV group is smaller; the dependent multiply chain remains. Sorting and string comparisons can dominate. |
| csvagg | Swag / GCC | Low | Swag shares the compact FNV lowering; numeric parsing, grouping and output ordering prevent a whole-program conclusion from hashing alone. |
| sha256 | Swag | High for the compression kernel, medium overall | Two rounds per 71-instruction interval, using 32-bit rotations and ANDN; GCC-v3 uses 65 instructions for one round. Several LLVM ports retain shift/OR sequences even with v3 enabled. |
| dijkstra | Swag / Clang | Low | Comparable compact heap sift paths; relaxation, heap growth and tie-dependent branches matter more than one instruction of difference. |
| raytrace | GCC | Low to medium | GCC keeps a compact sphere-intersection loop with little stack traffic. Other ports unroll or retain more intermediate state; branch frequencies, square roots and floating-point contracts remain decisive. |
| leven | Clang / GCC | Medium for a DP cell, low overall | Clang's observed cell interval has 13 instructions versus Swag's 17, with an extra stack access; initialization and loop dependency latency still matter. |
| chacha | Swag / Clang-v3 | High for the vector kernel, medium overall | Swag's register-only four-lane SIMD double round has 47 instructions versus Clang-v3's 53. Several other v3 ports retain scalar-heavy loops. |
| nbody | Clang-v3 | Medium for the step kernel, low overall | The observed fully unrolled step is shorter than Swag's, with similar memory traffic. Arithmetic dependencies and FP fusion rules prevent a speed ratio. |
| fannkuch | Swag / Clang | Low | Swag has compact rotation code but scalar permutation copies. GCC's wider copy is attractive, yet its rotation path calls memmove; copying alone cannot decide the winner. |
| binarytrees | Java C2 / CoreCLR | Low | Bump allocation can favor GC ports. Collection, manual reclamation, allocator caches and object layout differ, so this is a runtime/port hypothesis rather than a backend ranking. |
| lz77 | Swag / GCC | Low | Matching has data-dependent nested loops. Load placement, branch behavior and match length distributions need dynamic weighting; no defensible instruction-count winner. |
| sort | Swag / Clang | Low | Swag has shorter scalar scans, while Clang has a shorter surrounding partition interval. Their execution frequencies differ. |

This is not an exhaustive proof that another captured compiler cannot win a row. Go, Swift,
Rust, Zig, LDC and Odin remain fully available for inspection and subsequent timing; neither
absence from this shortlist nor larger function size establishes a loss. JIT output contains
multiple compilations and runtime-specific contracts. CPython bytecode is not comparable to
native instruction counts. There is no defensible single best compiler across these tasks.

## Reproducible kernel observations

Addresses below identify the archived executable, not a stable address for future builds.
Counts include instructions between the listed loop target and its back edge, inclusive.
They are static interval counts, not retired instructions, cycles or micro-operations.
Memory counts count instructions with memory operands; stack accesses include locals and
arguments and must not automatically be called spills.

| Task / capture | Interval | Work per interval | Instructions | Memory operands |
| --- | --- | --- | ---: | ---: |
| FNV, swag-release/wordfreq | 0x40bc00–0x40bc2e | Four input bytes | 11 | 4 |
| FNV, cpp-clang/wordfreq | 0x1760–0x17a2 | Four input bytes | 15 | 4 |
| SHA, swag-release/sha256 | 0x40db20–0x40dc2e | Two compression rounds | 71 | 4 |
| SHA, cpp-gcc-v3/sha256 | 0x15a0–0x1670 | One compression round | 65 | 2 |
| ChaCha, swag-release/chacha | 0x40db60–0x40dc30 | One four-lane double round | 47 | 0 |
| ChaCha, cpp-clang-v3/chacha | 0x1500–0x1618 | One four-lane double round | 53 | 0 |

Both ChaCha kernels execute ten double rounds per block, with no stack access inside those
intervals. Setup, output accumulation and checksum work are outside the quoted intervals.
The v3 Rust, Zig, LDC and Odin SHA round intervals respectively contain 69, 66, 74 and 74
instructions per round; enabling the ISA does not alone repair the observed rotate idiom.
This supports a concrete Swag strength, not a claim about every LLVM input or release.

For FNV, Swag folds the byte load into `xor al,[...]` before each multiply. Clang uses a
separate byte load and XOR. Both still execute four serial hash multiplications; fewer x86
instructions can have the same micro-operation count or critical path. For SHA, the difference
is more substantial: inspect operand width, rotate lowering, boolean algebra and two-round
unrolling together. Do not turn 71/2 versus 65 into a runtime speedup percentage.

Other checked observations:

- Swag's sort scans each use three instructions; Clang's use four. The surrounding partition
  back-edge intervals contain 20 and 17 instructions respectively. Nested scans make totals
  incomparable without branch counts.
- Swag's nbody step interval contains 314 instructions, 118 memory operands and 95 stack
  accesses. Clang-v3's corresponding fully unrolled step contains 285, 119 and 93. A scalar
  pair loop in another port must be weighted by its ten pairs before comparing it with a step.
- Fannkuch's Swag copy uses nine scalar load/store pairs. GCC's 72-byte copy uses four
  16-byte load/store pairs plus the tail, but a different hot path calls `memmove` for rotation.
  An earlier guarded SIMD-copy experiment regressed in timing and was reverted; the listing
  is a reason to investigate proven disjointness, not to restore that experiment blindly.
- All raytrace ports examined implement intersection over the sphere set, but unrolling and
  inlining change function boundaries. Whole-function length is not work per sphere.

## How to use this in the next campaign

Start with `python -B bench/scripts/codegen.py verify bench/disassembly/20261114-linux-x64
--check-sources` (on one command line). Display a complete listing with `show`, `--task` and
`--compiler`; add `--micro` for Swag Micro. Match source hashes, compiler binary, options,
ISA, ABI, safety, floating-point and allocation contracts before reusing a comparison.

Swag Micro includes lowered functions that may not survive linking. Use the linked native
listing to establish reachability, then use Micro to explain the lowering. Compare equal
work and separate cold checks/runtime scaffolding. For JITs select the relevant compiled
version; do not add all OSR/recompilation versions as if they executed together.

The next timing campaign should test the candidates above on a controlled host, run A/A
controls and validate checksums. Windows must collect its own complete listings and provenance,
including MSVC and NativeAOT where available. Linux artifacts are reusable static evidence,
not a substitute for Windows ABI/code-generation or runtime measurements.

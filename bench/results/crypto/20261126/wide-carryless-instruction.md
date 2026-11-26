# Paired 256-bit carry-less multiplication

The x86-64 backend adds an in-place operation that XORs two carry-less
products and an addend in each 128-bit lane of a 256-bit block. It reads
the complete input ranges before storing, including overlapping ranges,
and accepts unaligned pointers. The register allocator sees the three
volatile vector-register clobbers. The operation ends with `vzeroupper`.

Runtime feature discovery uses CPUID leaf 7, subleaf 0, ECX bit 10 for
VPCLMULQDQ under the existing AVX2 platform baseline. The native fixture
checks in-place, unaligned and overlapping inputs, and a live 128-bit
vector across emission. The x64 encoder test checks the emitted bytes.

| Validation | Result |
| --- | --- |
| Linux DevMode C++ | 1,751 passed |
| Linux native and JIT paired operation | Passed |
| Focused language reference | 14 passed |
| Micro comparison against preceding compiler | All 12 checksums matched |
| Windows COFF static library | Emitted and disassembled |

The standard DevMode selection excludes 135 optional filesystem tests.
The two synthetic functions whose generated names changed had identical
normalized bodies. Windows validation covered target emission and
register preservation in the emitted sequence. Execution ran on Linux.

[Language reference source](../../../../bin/reference/modules/language/src/004_009_simd.swg).

# 512-bit carry-less multiplication on x64

`Swag.vecCarrylessMul2XorQuad` folds two polynomial products and an
addend into four independent 128-bit lanes. It accepts unaligned and
overlapping input ranges. The encoder uses unmasked EVEX `vmovdqu64`,
`vpclmulqdq` and `vpternlogd`, ending with `vzeroupper`. The allocator
tracks the three volatile vector clobbers.

The runtime requires AVX-512F and VPCLMULQDQ on CPUID leaf 7 and XSAVE
and OSXSAVE on leaf 1. It also requires XCR0 mask `0xE6` to ensure that
the operating system preserves the XMM, YMM, opmask and upper ZMM state.
A regression test checks the implicit ECX input and EAX/EDX results of
`xgetbv` even though the instruction has no explicit operands.

| Validation | Result |
| --- | --- |
| Linux DevMode C++ with the independent IFMA extension | 1,752 passed, including XGETBV metadata |
| Linux Release compiler, JIT and native | 512-bit and 256-bit carry-less, full-width multiplication, and frame temporary tests passed |
| Linux DevMode compiler, JIT and native | 512-bit carry-less test passed |
| SIMD language reference | 15 passed in JIT and native |
| Micro workloads, Release and DevMode compiler comparisons | All 12 checksums matched in each comparison |
| Windows static library | COFF emitted and disassembled |

The C++ suite used the standard selection, which skips 135 optional
filesystem tests. The 512-bit fixture checks unaligned and overlapping
ranges and preserves a live 128-bit value across the instruction. On the
micro workloads, two generated helper names changed and a compile-time
segment length increased from `0x1100` to `0x1140`. The normalized native
workload bodies matched. Windows checks covered code emission. Native and
JIT execution ran on Linux.

[SIMD language reference source](../../../../bin/reference/modules/language/src/004_009_simd.swg).

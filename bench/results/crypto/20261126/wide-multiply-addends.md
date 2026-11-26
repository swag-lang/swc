# Full-width multiplication with two additive words

The five-argument `Swag.mulWide` overload computes the unsigned product
plus two independent 64-bit addends and splits the result into halves.
The largest possible value is `(2^64 - 1)^2 + 2(2^64 - 1) = 2^128 - 1`.
The original three-argument spelling continues to use the same lowering.
The x64 sequence feeds each low-word carry into the high half with `ADC`.

The integrated Release compiler contains the 512-bit carry-less
instructions and IFMA compiler changes through `c7629c28dd`, plus this
patch. Its SHA-256 is
`b60669af1a9771aea021e5effb8e2c16bbc7208e77bf1c5349b2120f8d3c0585`.
The combined DevMode compiler passed 1,752 C++ tests. Three focused
intrinsic tests passed in native and JIT Release and Release-safe. They
include maximum operands, two carries, a zero product and output aliasing.
The full language reference passed 526 cases in each execution mode.

All 10,593 wide arithmetic cases matched independent integer outputs.
The emitted Windows x64 COFF library contains the multiply and both
carry instructions. The twelve workload checksums matched. After
normalizing generated names and grouping overloaded functions by body,
the single differing instruction value was a type reference in a
compile-time persistence wrapper. The native workload bodies matched.

[Micro comparison](wide-multiply-addends-micro.txt) · [Normalized body audit](wide-multiply-addends-audit.json) · [Original multiply](wide-multiply-instruction.md)

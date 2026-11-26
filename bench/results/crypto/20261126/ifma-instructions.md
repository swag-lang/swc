# Packed 52-bit unsigned multiply-add on x64

The Release and DevMode compilers emit XMM forms of `VPMADD52LUQ` and
`VPMADD52HUQ`. Each lane multiplies the low 52 bits of its inputs and
adds the selected product half to a 64-bit accumulator. The backend
tracks the accumulator as a read and a write. The encoder tests cover
both opcodes, including an encoding with extended register numbers.

The feature check requires AVX-512F, IFMA and AVX-512VL in CPUID plus
the AVX-512 state enabled in XCR0. It shares the operating-system
state check introduced for 512-bit CRC folding. Feature-mask tests
cleared the IFMA bit, the AVX-512VL bit, OSXSAVE or the upper vector
state in separate runs. Each configuration selected the fallback
in native execution and in the JIT. A required-feature arithmetic
test passed in both modes on the available EPYC host. Windows COFF
disassembly also contained both packed instructions and XGETBV.

Linux DevMode passed 1,752 C++ tests. The standard C++ run reproduced
the allocator diagnostic for the existing oversized-allocation fixture.
The 526-case native language reference and the focused frame-boundary
test passed. Both Release and DevMode Microdiff runs matched the
12 standard benchmark checksums. The normalized DevMode benchmark
bodies were identical, with deltas limited to generated names and the
size of a shared compile-time data segment.

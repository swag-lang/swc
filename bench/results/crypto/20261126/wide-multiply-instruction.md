# Full-width unsigned multiplication

The native intrinsic lowers an unsigned 64-bit product to two 64-bit outputs
with the x64 MUL instruction. Micro tracks both outputs through register
allocation and dead-code elimination.

Linux DevMode passed all 1,751 C++ tests, including the encoder checks. Two
intrinsic cases passed in native and JIT builds, covering maximum operands,
aliasing and an unused low half. The full 524-case language reference passed.
The twelve standard benchmarks matched checksums and final Micro counts. The
observed listing differences were generated runtime symbol names.

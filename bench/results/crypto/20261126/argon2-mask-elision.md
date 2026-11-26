# Redundant low-word masks in Argon2id

BlaMka multiplies the low 32 bits of each 64-bit lane. The compiler
already selected the widening multiply and this change lets it consume
the original register when a mask preserves all 32 low bits. The
compiler captures the operand at its original evaluation point.
Masks that also clear low bits keep that masking operation.

In the Argon2 compression function, final Micro fell from 430 to 361
instructions and from 76 to 71 memory operands. The native executable
retained 32 widening multiply instructions and contained 64 fewer
packed AND instructions across the two permutation loops.

Both builds in each comparison used the same native Release program
configuration and standard-library snapshot. Runs used one worker on
CPU 2 of an AMD EPYC 9V74 under Linux 6.18.57. Each call used four lanes,
three passes, Argon2 version 0x13 and a 32-byte tag. Every tag matched.
The tables show median process CPU milliseconds and paired 95% time
ratios. The libargon2 reference is release 20190702 built with GCC
14.2 for Zen 4 using its AVX-512 kernel.

## VPCLMUL compiler baseline

The first comparison used compiler `44e09064f1` and library
`da13763b7b`. It ran thirteen pairs for 1 and 64 MiB and eleven
pairs for 256 MiB. OpenSSL 3.5.7 is included in the raw samples.

| MiB | Baseline | Elided masks | libargon2 AVX-512 | OpenSSL 4.1.0 | Candidate / baseline | Candidate / libargon2 |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 1.404 | 1.197 | 0.827 | 1.591 | 0.847 [0.815, 0.904] | 1.446 [1.407, 1.511] |
| 64 | 122.586 | 107.621 | 88.971 | 144.574 | 0.878 [0.426, 0.919] | 1.226 [1.187, 1.272] |
| 256 | 731.600 | 619.765 | 456.391 | 722.681 | 0.893 [0.631, 1.023] | 1.364 [0.711, 1.497] |

Swag used 15.3% less CPU at 1 MiB and 12.2% less at 64 MiB.
The paired 256 MiB interval included parity with the Swag baseline.
All three profiles used less CPU than OpenSSL 4.1.0. The tuned
libargon2 build had the lowest median in all three.

## Replay with the EVEX and IFMA compiler

The replay ran eleven pairs using compiler `c7629c28dd` and
library `86cfe53193`. Both executables share the same compiler
objects through the IFMA campaign apart from the binary code generation
translation unit.

| MiB | Baseline | Elided masks | libargon2 AVX-512 | OpenSSL 4.1.0 | Candidate / baseline | Candidate / libargon2 |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 1.372 | 1.212 | 0.832 | 1.595 | 0.884 [0.850, 0.890] | 1.468 [1.369, 1.485] |
| 64 | 122.219 | 111.611 | 94.393 | 148.256 | 0.913 [0.902, 0.991] | 1.189 [1.149, 1.352] |

The replay confirmed 11.6% less CPU at 1 MiB and 8.7% less at 64 MiB.

## Validation

All twelve benchmark checksums and final Micro listings matched after
normalizing two generated helper renames per task. The check passed
against the original compiler, the EVEX compiler and the combined
EVEX/IFMA compiler. The latter passed 164 focused Core cryptography
tests in each of native Release and Release-safe and 17 native and
17 JIT SIMD cases. The SIMD regression exercises partial masks and
a right operand that changes the left operand’s original storage.
The original DevMode compiler with this change passed its C++ suite.

[Argon2 reproduction](../../../workloads/argon2/README.md#comparing-openssl-versions) · [Raw times and tags](argon2-mask-elision.json)

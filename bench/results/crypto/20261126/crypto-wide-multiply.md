# Full-width multiplication in public-key arithmetic

The Core unsigned 64-bit multiply helper now lowers to one x86-64 multiply
that provides both halves. Curve25519, Ed25519 and P-256 use the same helper
and retain their existing multiplication and reduction bounds.

Both Swag builds used the same native Release compiler and library tree
with only the helper changed. There were 11 paired process CPU-time trials
on AMD EPYC 9V74 CPU 3, targeting 25 ms. The common workload compared the
full outputs to OpenSSL 3.5.7. The compiler report records the generated
instruction checks. The Core native Release and Release-safe suites each
passed 53 focused cases with the wrapper.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| x25519-public | 32 | 0 | wide-mul | software | ops/s | 4.31e+03 | 3.39e+03 | 1.28 [1.25, 1.29] |
| x25519-shared | 32 | 0 | wide-mul | software | ops/s | 4.32e+03 | 3.35e+03 | 1.27 [1.22, 1.31] |
| ed25519-public | 32 | 0 | wide-mul | software | ops/s | 8.19e+03 | 6.34e+03 | 1.29 [1.28, 1.32] |
| ed25519-sign | 64 | 0 | wide-mul | software | ops/s | 3.42e+03 | 2.78e+03 | 1.24 [1.21, 1.26] |
| ed25519-sign | 4096 | 0 | wide-mul | software | ops/s | 3.18e+03 | 2.59e+03 | 1.22 [1.2, 1.25] |
| p256-public | 32 | 0 | wide-mul | software | ops/s | 5.57e+03 | 4.08e+03 | 1.37 [1.3, 1.4] |
| p256-sign | 64 | 0 | wide-mul | software | ops/s | 5.04e+03 | 3.51e+03 | 1.43 [1.37, 1.48] |
| p256-sign | 4096 | 0 | wide-mul | software | ops/s | 4.86e+03 | 3.5e+03 | 1.38 [1.34, 1.41] |

[Raw samples and output fingerprints](crypto-wide-multiply.json) · [Compiler validation](wide-multiply-instruction.md).

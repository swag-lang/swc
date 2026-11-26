# Unified P-256 point addition in fixed windows

The arbitrary-point multiplier keeps homogeneous projective coordinates
and uses complete addition for the selected table value. Every four-bit
window still scans the full list of nonzero entries with masks. The
shorter doubling formula preserves the representation of infinity with
a mask. The result converts to Jacobian coordinates for its caller.

The paired native Release panel used 17 process CPU-time rounds on AMD
EPYC 9V74 CPU 4. It compared complete outputs with OpenSSL 3.5.7 and
OpenSSL 4.1.0. ECDH improved 7%, and the valid verification profiles
improved about 6%.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| p256-ecdh | 32 | 0 | unified | jacobian | ops/s | 3.7e+03 | 3.46e+03 | 1.07 [1.07, 1.1] |
| p256-verify | 64 | 0 | unified | jacobian | ops/s | 2.73e+03 | 2.59e+03 | 1.06 [1.01, 1.07] |
| p256-verify | 4096 | 0 | unified | jacobian | ops/s | 2.74e+03 | 2.54e+03 | 1.06 [1.06, 1.08] |
| p256-public | 32 | 0 | unified | jacobian | ops/s | 1.03e+04 | 9.93e+03 | 1.04 [1.02, 1.05] |
| p256-sign | 64 | 0 | unified | jacobian | ops/s | 8.28e+03 | 8.01e+03 | 1.04 [1.02, 1.05] |
| p256-sign | 4096 | 0 | unified | jacobian | ops/s | 7.85e+03 | 7.76e+03 | 1.01 [0.938, 1.03] |

A separate exact OpenSSL 4.1.0 check varied both ECDH scalars over all
256 single-bit positions, 36 pairs near the order and one, and 128
deterministic random pairs. All 420 shared secrets matched. The seven
focused cases passed in JIT and native Release and Release-safe.

The code uses the complete projective addition and the shorter
projective doubling documented in the formula database. [Renes, Costello and Batina](https://eprint.iacr.org/2015/1060) · [Explicit-Formulas Database](https://www.hyperelliptic.org/EFD/g1p/auto-shortw-projective-3.html).

[Raw paired trials](p256-unified-windows.json) · [ECDH verification fixtures](p256-unified-windows-verification.json).

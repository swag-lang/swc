# Affine Curve25519 generator table

The fixed-base generator table stores affine coordinates. The mixed
addition reconstructs the required projective terms while keeping the
masked full table scan. Ed25519 uses it for public-key generation and
signing. X25519 uses it for public-key generation.

The common native Release workload ran 11 paired process CPU-time trials
on AMD EPYC 9V74 CPU 3. Complete outputs matched both OpenSSL 3.5.7 and
libsodium 1.0.18. Signing includes deriving the per-call key from its seed.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| x25519-public | 32 | 0 | ed-affine-fast | libsodium | ops/s | 1.52e+04 | 3.54e+04 | 0.429 [0.418, 0.441] |
| x25519-public | 32 | 0 | ed-affine-fast | projective | ops/s | 1.52e+04 | 1.3e+04 | 1.16 [1.14, 1.18] |
| ed25519-public | 32 | 0 | ed-affine-fast | libsodium | ops/s | 1.5e+04 | 6.19e+04 | 0.241 [0.227, 0.245] |
| ed25519-public | 32 | 0 | ed-affine-fast | projective | ops/s | 1.5e+04 | 1.28e+04 | 1.15 [1.13, 1.28] |
| ed25519-sign | 64 | 0 | ed-affine-fast | libsodium | ops/s | 5.46e+03 | 2.88e+04 | 0.19 [0.183, 0.218] |
| ed25519-sign | 64 | 0 | ed-affine-fast | projective | ops/s | 5.46e+03 | 4.86e+03 | 1.12 [1.09, 1.16] |
| ed25519-sign | 4096 | 0 | ed-affine-fast | libsodium | ops/s | 4.93e+03 | 2.05e+04 | 0.241 [0.235, 0.245] |
| ed25519-sign | 4096 | 0 | ed-affine-fast | projective | ops/s | 4.93e+03 | 4.47e+03 | 1.11 [1.08, 1.15] |

Ten focused cases passed in each native Release configuration. Another
24 untimed differential cases matched OpenSSL.

[Raw trials and output fingerprints](ed25519-affine-generator.json).

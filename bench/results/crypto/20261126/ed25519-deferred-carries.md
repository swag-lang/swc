# Deferred carries in Edwards formulas

The shared Curve25519 field permits bounded Edwards sums and differences
to flow directly into the following products. The same constant-time
selection and public-key validation paths use these ranges.

The native Release workload verified all five measured outputs against
OpenSSL 3.5.7 and libsodium 1.0.22. X25519 public keys reached 34,600
operations per second. Ed25519 signing of 64 bytes reached 16,800
operations per second.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| x25519-public | 32 | 0 | ed-loose-products | libsodium | ops/s | 3.46e+04 | 6.05e+04 | 0.558 [0.542, 0.597] |
| x25519-public | 32 | 0 | ed-loose-products | ed-verify-final | ops/s | 3.46e+04 | 2.74e+04 | 1.23 [1.19, 1.55] |
| x25519-shared | 32 | 0 | ed-loose-products | libsodium | ops/s | 1.39e+04 | 3.23e+04 | 0.427 [0.414, 0.46] |
| x25519-shared | 32 | 0 | ed-loose-products | ed-verify-final | ops/s | 1.39e+04 | 1.38e+04 | 1.01 [0.979, 1.02] |
| ed25519-public | 32 | 0 | ed-loose-products | libsodium | ops/s | 3.4e+04 | 6.1e+04 | 0.56 [0.547, 0.563] |
| ed25519-public | 32 | 0 | ed-loose-products | ed-verify-final | ops/s | 3.4e+04 | 2.79e+04 | 1.22 [1.19, 1.28] |
| ed25519-sign | 64 | 0 | ed-loose-products | libsodium | ops/s | 1.68e+04 | 2.95e+04 | 0.568 [0.56, 0.595] |
| ed25519-sign | 64 | 0 | ed-loose-products | ed-verify-final | ops/s | 1.68e+04 | 1.38e+04 | 1.22 [1.2, 1.26] |
| ed25519-sign | 4096 | 0 | ed-loose-products | libsodium | ops/s | 1.24e+04 | 2.06e+04 | 0.605 [0.59, 0.613] |
| ed25519-sign | 4096 | 0 | ed-loose-products | ed-verify-final | ops/s | 1.24e+04 | 1.06e+04 | 1.16 [1.15, 1.19] |

A separate single-worker comparison verified a fixed 40-byte message.
Median Swag process CPU time fell from 243.96 to 194.27 µs per valid
signature. OpenSSL measured 110.23 µs and libsodium 54.02 µs there.
Ten focused cases passed in both native Release configurations, and
24 additional outputs matched OpenSSL.

[Raw paired trials](ed25519-deferred-carries.json) · [Verification timing](ed25519-deferred-carries-verification-timing.json) · [External verification timing](ed25519-deferred-carries-references.log).

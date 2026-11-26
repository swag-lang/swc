# Packed Curve25519 generator table selection

The fixed-base table places each pair of candidates in vector lanes.
The masked selection still inspects all eight public table entries,
and serves both Ed25519 and X25519 generator multiplication.

The native Release workload matched all measured results with OpenSSL
3.5.7 and libsodium 1.0.22. Public-key generation increased by about 10%
for both algorithms, and signing by 8–9%.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| x25519-public | 32 | 0 | ed-transposed-selection | libsodium | ops/s | 3.84e+04 | 6.33e+04 | 0.606 [0.592, 0.609] |
| x25519-public | 32 | 0 | ed-transposed-selection | ed-loose-products | ops/s | 3.84e+04 | 3.49e+04 | 1.1 [1.07, 1.1] |
| x25519-shared | 32 | 0 | ed-transposed-selection | libsodium | ops/s | 1.4e+04 | 3.28e+04 | 0.429 [0.426, 0.464] |
| x25519-shared | 32 | 0 | ed-transposed-selection | ed-loose-products | ops/s | 1.4e+04 | 1.4e+04 | 1 [1, 1.01] |
| ed25519-public | 32 | 0 | ed-transposed-selection | libsodium | ops/s | 3.76e+04 | 6.14e+04 | 0.607 [0.58, 0.615] |
| ed25519-public | 32 | 0 | ed-transposed-selection | ed-loose-products | ops/s | 3.76e+04 | 3.41e+04 | 1.1 [1.04, 1.14] |
| ed25519-sign | 64 | 0 | ed-transposed-selection | libsodium | ops/s | 1.81e+04 | 2.95e+04 | 0.615 [0.606, 0.902] |
| ed25519-sign | 64 | 0 | ed-transposed-selection | ed-loose-products | ops/s | 1.81e+04 | 1.66e+04 | 1.09 [1.08, 1.1] |
| ed25519-sign | 4096 | 0 | ed-transposed-selection | libsodium | ops/s | 1.32e+04 | 2.03e+04 | 0.644 [0.616, 0.67] |
| ed25519-sign | 4096 | 0 | ed-transposed-selection | ed-loose-products | ops/s | 1.32e+04 | 1.22e+04 | 1.08 [1.02, 1.12] |

Ten focused cases passed in each native Release configuration. Twenty-four
additional external cases matched OpenSSL.

[Raw trials and output fingerprints](ed25519-vector-selection.json).

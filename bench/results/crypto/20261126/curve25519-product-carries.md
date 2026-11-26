# Streaming Curve25519 product carries

The radix-51 field multiplication and squaring pass each wide partial
product into the next carry as soon as its column is complete. This
reduces live storage inside the same schedule. Both X25519 and Ed25519
use the field implementation.

The common native Release workload compared complete outputs with
OpenSSL 3.5.7 and libsodium 1.0.18. X25519 shared-secret throughput
increased from 9,160 to 13,900 operations per second on this host.
OpenSSL measured about 14,000 and libsodium 32,800.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| x25519-public | 32 | 0 | curve-stream-final | libsodium | ops/s | 2.8e+04 | 3.47e+04 | 0.816 [0.767, 0.836] |
| x25519-public | 32 | 0 | curve-stream-final | buffered | ops/s | 2.8e+04 | 2.35e+04 | 1.19 [1.17, 1.23] |
| x25519-shared | 32 | 0 | curve-stream-final | libsodium | ops/s | 1.39e+04 | 3.28e+04 | 0.424 [0.393, 0.433] |
| x25519-shared | 32 | 0 | curve-stream-final | buffered | ops/s | 1.39e+04 | 9.16e+03 | 1.52 [1.5, 1.78] |
| ed25519-public | 32 | 0 | curve-stream-final | libsodium | ops/s | 2.8e+04 | 6.09e+04 | 0.457 [0.44, 0.473] |
| ed25519-public | 32 | 0 | curve-stream-final | buffered | ops/s | 2.8e+04 | 2.33e+04 | 1.19 [1.15, 1.22] |
| ed25519-sign | 64 | 0 | curve-stream-final | libsodium | ops/s | 1.37e+04 | 2.98e+04 | 0.464 [0.443, 0.477] |
| ed25519-sign | 64 | 0 | curve-stream-final | buffered | ops/s | 1.37e+04 | 1.14e+04 | 1.2 [1.14, 1.25] |
| ed25519-sign | 4096 | 0 | curve-stream-final | libsodium | ops/s | 1.08e+04 | 2.08e+04 | 0.517 [0.508, 0.525] |
| ed25519-sign | 4096 | 0 | curve-stream-final | buffered | ops/s | 1.08e+04 | 9.32e+03 | 1.15 [1.13, 1.17] |

Ten focused cases passed in each native Release configuration. Twenty-four
additional independent cases matched OpenSSL.

[Raw trials and output fingerprints](curve25519-product-carries.json).

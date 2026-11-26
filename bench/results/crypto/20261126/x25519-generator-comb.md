# X25519 public keys with the masked generator table

The X25519 public-key path uses the existing Edwards fixed-base comb and
converts the result to the Montgomery coordinate. The table lookup scans
every entry under a mask. The shared-secret operation still uses the
Montgomery ladder for arbitrary input points.

Both builds already include bounded field carries and full-width word
multiplication. The rates below come from paired process CPU-time trials on
AMD EPYC 9V74 that compared the complete public key or shared secret to
OpenSSL 3.5.7.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| x25519-public | 32 | 0 | baseline | OpenSSL | ops/s | 7.24e+03 | 2.77e+04 | 0.261 [0.257, 0.265] |
| x25519-public | 32 | 0 | masked-edwards | OpenSSL | ops/s | 1.3e+04 | 2.77e+04 | 0.47 [0.465, 0.486] |
| x25519-public | 32 | 0 | masked-edwards | baseline | ops/s | 1.3e+04 | 7.24e+03 | 1.81 [1.77, 1.85] |
| x25519-shared | 32 | 0 | baseline | OpenSSL | ops/s | 7.28e+03 | 1.44e+04 | 0.508 [0.498, 0.516] |
| x25519-shared | 32 | 0 | masked-edwards | OpenSSL | ops/s | 7.37e+03 | 1.44e+04 | 0.512 [0.505, 0.523] |
| x25519-shared | 32 | 0 | masked-edwards | baseline | ops/s | 7.37e+03 | 7.28e+03 | 1.02 [0.986, 1.03] |
| x25519-public | 32 | 0 | baseline | OpenSSL | ops/s | 7.24e+03 | 2.77e+04 | 0.261 [0.257, 0.265] |
| x25519-shared | 32 | 0 | baseline | OpenSSL | ops/s | 7.28e+03 | 1.44e+04 | 0.508 [0.498, 0.516] |

Ten focused cases passed in both native Release configurations. Another 24
external OpenSSL comparisons matched.

[Raw trials and output fingerprints](x25519-generator-comb.json).

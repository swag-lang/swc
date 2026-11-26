# X25519 ladder with deferred carries

The Montgomery ladder keeps sums and differences within the documented
bounds of the following field multiplication and squaring. It performs
the fixed sequence of 255 ladder steps and the same masked exchanges.

The paired native Release workload used the same full-width multiplication
compiler for both builds and checked the complete outputs against
OpenSSL 3.5.7.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| x25519-public | 32 | 0 | baseline | OpenSSL | ops/s | 1.32e+04 | 2.78e+04 | 0.475 [0.46, 0.48] |
| x25519-public | 32 | 0 | loose-ladder | OpenSSL | ops/s | 1.32e+04 | 2.78e+04 | 0.475 [0.471, 0.478] |
| x25519-public | 32 | 0 | loose-ladder | baseline | ops/s | 1.32e+04 | 1.32e+04 | 1 [0.991, 1.03] |
| x25519-shared | 32 | 0 | baseline | OpenSSL | ops/s | 7.3e+03 | 1.41e+04 | 0.518 [0.512, 0.571] |
| x25519-shared | 32 | 0 | loose-ladder | OpenSSL | ops/s | 9.85e+03 | 1.41e+04 | 0.698 [0.683, 0.764] |
| x25519-shared | 32 | 0 | loose-ladder | baseline | ops/s | 9.85e+03 | 7.3e+03 | 1.35 [1.33, 1.36] |

Ten focused cases passed in each native Release configuration. Another 24
OpenSSL comparisons matched, including inputs near the field prime.

[Raw trials and output fingerprints](x25519-ladder-carries.json).

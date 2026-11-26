# Bounded Curve25519 field carries

The shared Curve25519 field implementation keeps radix-51 limbs within the
bounds required for addition, subtraction and multiplication, with canonical
reduction at the comparison and byte-encoding boundaries. X25519 and Ed25519
both use this field. The scalar schedule and selection stay independent of
secret data.

Both builds use the published full-width multiplication helper. The table
shows paired process CPU-time trials on AMD EPYC 9V74 and complete output
comparisons to OpenSSL 3.5.7.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| x25519-public | 32 | 0 | bounded-carries | baseline | ops/s | 7.09e+03 | 4.15e+03 | 1.71 [1.65, 1.75] |
| x25519-shared | 32 | 0 | bounded-carries | baseline | ops/s | 6.98e+03 | 4.17e+03 | 1.67 [1.61, 1.71] |
| ed25519-public | 32 | 0 | bounded-carries | baseline | ops/s | 1.28e+04 | 7.99e+03 | 1.57 [1.54, 1.64] |
| ed25519-sign | 64 | 0 | bounded-carries | baseline | ops/s | 4.97e+03 | 3.37e+03 | 1.46 [1.43, 1.52] |
| ed25519-sign | 4096 | 0 | bounded-carries | baseline | ops/s | 4.56e+03 | 3.22e+03 | 1.41 [1.39, 1.43] |

Ten focused cases passed in each native Release configuration, including
low-order X25519 inputs adjacent to the field prime. Another 24 outputs
matched OpenSSL. A separate Ed25519 verification measurement fell from
693 to 426 microseconds per verification.

[Raw trials and output fingerprints](curve25519-bounded-carries.json).

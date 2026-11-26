# Signed affine Curve25519 generator tables

Each generator column uses a signed representation and eight affine points.
Every lookup scans all eight entries with masks, and the sign is applied using
field arithmetic. The fixed-base primitive is shared by Ed25519 and X25519.

Both builds include the same mixed affine and projective addition. Eleven paired
native Release process CPU-time trials ran on AMD EPYC 9V74 CPU 3. Rates are
operations per second, with the same input, seed and output in each implementation.

| Operation | Bytes | Affine | Signed affine | OpenSSL 3.5.7 | libsodium 1.0.18 | Paired speedup (95% CI) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| x25519-public | 32 | 1.517e+04 | 2.343e+04 | 2.762e+04 | 3.535e+04 | 1.54 [1.46, 1.58] |
| ed25519-public | 32 | 1.495e+04 | 2.349e+04 | 2.689e+04 | 6.186e+04 | 1.57 [1.54, 1.69] |
| ed25519-sign | 64 | 5462 | 7419 | 1.272e+04 | 2.883e+04 | 1.36 [1.31, 1.41] |
| ed25519-sign | 4096 | 4927 | 6531 | 1.183e+04 | 2.045e+04 | 1.33 [1.3, 1.36] |

All measured outputs matched both external references. Another 24 cases
matched OpenSSL, and ten focused cases passed in each native Release configuration.

[Raw trials and output fingerprints](ed25519-affine-generator.json).

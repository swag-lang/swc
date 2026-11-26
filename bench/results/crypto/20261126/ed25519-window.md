# Ed25519 masked four-bit scalar windows

The scalar multiplication scans all precomputed multiples and masks the selection
for each window. Generated Micro confirmed a masked choice and a public loop index.
The four focused native Ed25519 tests passed in Release and Release-safe, with 24
additional OpenSSL key, signature and verification comparisons.

Twenty interleaved process CPU-time samples per version ran on AMD EPYC 9V74 CPU 3.

| Operation | Before (µs) | After (µs) | Paired speedup (95% CI) |
| --- | ---: | ---: | ---: |
| Public key | 552.45 | 345.39 | 1.603 [1.561, 1.668] |
| Sign | 1148.39 | 758.27 | 1.489 [1.471, 1.533] |
| Verify | 2421.65 | 1654.13 | 1.473 [1.454, 1.498] |

OpenSSL 3.5.7 verified the synthetic test message in 114 µs in a separate direct
EVP measurement.

[Raw trials](ed25519-window.json).

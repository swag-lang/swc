# Four-product reciprocal GHASH

GHASH accumulates four carry-less products and reduces them together. Nine native
Core AES-GCM tests passed in Release and Release-safe. The verifier matched OpenSSL
3.5.7 on 56 additional combinations of size and alignment. The timed baseline
already includes four-counter AES-NI encryption.

On CPU 2 of the AMD EPYC 9V74, the common workload used 11 paired process CPU-time
trials per size. Every measured output matched. Rates are decimal GB/s.

| Bytes | Before | After | OpenSSL | Paired speedup (95% CI) |
| ---: | ---: | ---: | ---: | ---: |
| 64 | 0.155 | 0.158 | 0.181 | 1.02 [0.955, 1.3] |
| 4096 | 1.65 | 2.51 | 5.2 | 1.52 [1.47, 1.55] |
| 65536 | 1.92 | 3.05 | 9.76 | 1.58 [1.5, 1.7] |
| 1048576 | 1.92 | 3.25 | 10.1 | 1.66 [1.39, 1.95] |

[Raw trials and output fingerprints](aes-reciprocal.json).

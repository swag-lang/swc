# Direct SHA-3 and SHAKE sponge input

SHA-3 and SHAKE now share one sponge path, absorb full-rate blocks directly and
copy output in native byte order on little-endian targets. All ten focused native
Release Core tests passed, including HMAC, KMAC, partial updates and multi-block
SHAKE output. The timed baseline includes the fixed-lane permutation.

On CPU 4 of the AMD EPYC 9V74, the common workload used 11 paired process CPU-time
trials per size. Every measured output matched. Rates are decimal GB/s.

| Bytes | Before | After | OpenSSL | Paired speedup (95% CI) |
| ---: | ---: | ---: | ---: | ---: |
| 64 | 0.124 | 0.134 | 0.196 | 1.08 [0.973, 1.12] |
| 136 | 0.151 | 0.167 | 0.23 | 1.1 [1.07, 1.14] |
| 4096 | 0.331 | 0.378 | 0.485 | 1.13 [1.03, 1.21] |
| 65536 | 0.341 | 0.384 | 0.49 | 1.13 [1.09, 1.16] |
| 1048576 | 0.338 | 0.387 | 0.488 | 1.14 [1.11, 1.16] |

[Raw trials and output fingerprints](sha3-direct.json).

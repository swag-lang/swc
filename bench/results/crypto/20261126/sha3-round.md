# Keccak rounds with fixed lane positions

The permutation uses fixed lane positions and native constant rotates. The ten
selected Core tests for SHA-3, SHAKE, HMAC-SHA-3, and KMAC passed in native Release.
SHA3-256 also matched OpenSSL 3.5.7 at 21 additional sizes and byte offsets around
its 136-byte absorb rate.

On CPU 4 of the AMD EPYC 9V74, the common workload used 11 paired process CPU-time
trials per size. Every measured output matched. Rates are decimal GB/s.

| Bytes | Before | After | OpenSSL | Paired speedup (95% CI) |
| ---: | ---: | ---: | ---: | ---: |
| 64 | 0.0443 | 0.122 | 0.197 | 2.66 [2.04, 2.81] |
| 4096 | 0.105 | 0.329 | 0.468 | 3.13 [2.95, 3.18] |
| 65536 | 0.109 | 0.346 | 0.497 | 3.17 [2.93, 3.25] |
| 1048576 | 0.106 | 0.337 | 0.483 | 3.17 [3.03, 3.33] |

[Raw trials and output fingerprints](sha3-round.json).

# MD5 wide loads and direct blocks

Full blocks now enter compression directly and the compressor uses wide little-endian
loads and typed rotates. Both focused native Release Core tests passed, including RFC
vectors, streaming and the length counter. MD5 also matched OpenSSL 3.5.7 on 27
additional cases at three byte offsets around block and padding boundaries.

On CPU 4 of the AMD EPYC 9V74, the common workload used 11 paired process CPU-time
trials per size. Every measured output matched. Rates are decimal GB/s.

| Bytes | Before | After | OpenSSL | Paired speedup (95% CI) |
| ---: | ---: | ---: | ---: | ---: |
| 16 | 0.101 | 0.119 | 0.146 | 1.18 [1.13, 1.27] |
| 64 | 0.197 | 0.234 | 0.328 | 1.2 [1.11, 1.26] |
| 4096 | 0.44 | 0.495 | 0.774 | 1.12 [1.1, 1.13] |
| 65536 | 0.454 | 0.508 | 0.798 | 1.12 [1.11, 1.15] |
| 1048576 | 0.444 | 0.504 | 0.787 | 1.13 [1.12, 1.16] |

[Raw trials and output fingerprints](md5-wide.json).

# AES-GCM four-counter encryption

AES-GCM keeps four independent counter blocks in flight on the AES-NI path.
Nine native Core AES-GCM tests passed in Release and Release-safe. The added
OpenSSL vector covers a 145-byte unaligned exact-in-place record, guard bytes and
no writes on a bad tag. An additional 56 inputs matched OpenSSL 3.5.7.
The baseline already includes the guarded AES-NI block path.

On CPU 2 of the AMD EPYC 9V74, the common workload used 11 paired process CPU-time
trials per size. Every measured output matched. Rates are decimal GB/s.

| Bytes | Before | After | OpenSSL | Paired speedup (95% CI) |
| ---: | ---: | ---: | ---: | ---: |
| 64 | 0.115 | 0.158 | 0.176 | 1.37 [1.05, 1.54] |
| 4096 | 0.316 | 1.56 | 4.97 | 4.96 [4.82, 8.4] |
| 65536 | 0.322 | 1.89 | 9.72 | 5.85 [5.58, 6.31] |
| 1048576 | 0.324 | 1.93 | 10.1 | 5.83 [5.62, 10.2] |

[Raw trials and output fingerprints](aes-batched.json).

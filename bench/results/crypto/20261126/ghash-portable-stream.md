# Portable GHASH with persistent field state

The portable GHASH path keeps its accumulator and hash key in field-word
order across all blocks of a message. Multiplication uses a fixed arithmetic
schedule. The keyed state is explicitly cleared at the end of its lifetime.

The common test forced Swag's PCLMUL dispatch off and masked OpenSSL's
carry-less multiply capability. It measured process CPU time with complete
ciphertext and tag comparisons. At 1 MiB, associated-data-only GCM rose from
0.072 to 0.220 GB/s and full GCM from 0.0718 to 0.213 GB/s. The corresponding
OpenSSL 3.5.7 rates were 0.583 and 0.539 GB/s.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| aes-256-gcm-aad | 1048576 | 0 | bitwise | OpenSSL | GB/s | 0.072 | 0.583 | 0.125 [0.105, 0.126] |
| aes-256-gcm-aad | 1048576 | 0 | scalar-stream | OpenSSL | GB/s | 0.22 | 0.583 | 0.378 [0.374, 0.381] |
| aes-256-gcm-aad | 1048576 | 0 | scalar-stream | bitwise | GB/s | 0.22 | 0.072 | 3.02 [3, 3.62] |
| aes-256-gcm | 1048576 | 0 | bitwise | OpenSSL | GB/s | 0.0718 | 0.539 | 0.134 [0.101, 0.135] |
| aes-256-gcm | 1048576 | 0 | scalar-stream | OpenSSL | GB/s | 0.213 | 0.539 | 0.394 [0.389, 0.403] |
| aes-256-gcm | 1048576 | 0 | scalar-stream | bitwise | GB/s | 0.213 | 0.0718 | 2.95 [2.93, 3.92] |

Nine focused cases passed in native Release and Release-safe. The same
nine passed in QEMU Release with PCLMUL masked, and in Release-safe with
both AES and PCLMUL masked. The external sweep included 56 unaligned
associated-data cases and 56 unaligned GCM cases.

[Raw paired trials](ghash-portable-stream.json) · [External verification cases](ghash-portable-stream-verification.json).

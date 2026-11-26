# Explicit Poly1305 limb reduction

The scalar and grouped polynomial paths share one explicit five-limb
carry reduction. At 1023 bytes, throughput increased from 1.23 to 1.30
GB/s with a paired gain of 1.06× [1.05, 1.08]. The long-buffer profiles
had similar throughput.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| poly1305 | 64 | 1 | unrolled | baseline | GB/s | 0.425 | 0.422 | 1 [0.982, 1.03] |
| poly1305 | 256 | 1 | unrolled | baseline | GB/s | 0.943 | 0.912 | 1.03 [1.02, 1.07] |
| poly1305 | 512 | 1 | unrolled | baseline | GB/s | 1.16 | 1.1 | 1.04 [0.991, 1.08] |
| poly1305 | 1023 | 1 | unrolled | baseline | GB/s | 1.3 | 1.23 | 1.06 [1.05, 1.08] |
| poly1305 | 1024 | 1 | unrolled | baseline | GB/s | 1.4 | 1.39 | 1.07 [0.93, 1.16] |
| poly1305 | 4096 | 1 | unrolled | baseline | GB/s | 2.37 | 2.32 | 1.03 [0.985, 1.04] |
| poly1305 | 4194304 | 1 | unrolled | baseline | GB/s | 2.9 | 2.93 | 0.994 [0.97, 1.01] |
| chacha20-poly1305 | 64 | 1 | unrolled | baseline | GB/s | 0.131 | 0.133 | 0.998 [0.905, 1.02] |
| chacha20-poly1305 | 256 | 1 | unrolled | baseline | GB/s | 0.358 | 0.353 | 1.01 [0.972, 1.08] |
| chacha20-poly1305 | 512 | 1 | unrolled | baseline | GB/s | 0.472 | 0.479 | 0.988 [0.932, 1.01] |
| chacha20-poly1305 | 1023 | 1 | unrolled | baseline | GB/s | 0.479 | 0.47 | 1.01 [0.988, 1.11] |
| chacha20-poly1305 | 1024 | 1 | unrolled | baseline | GB/s | 0.599 | 0.57 | 1.04 [1.03, 1.06] |
| chacha20-poly1305 | 4096 | 1 | unrolled | baseline | GB/s | 0.799 | 0.8 | 0.999 [0.971, 1.01] |
| chacha20-poly1305 | 4194304 | 1 | unrolled | baseline | GB/s | 0.837 | 0.876 | 0.965 [0.701, 1.13] |

Four-worker Release and Release-safe each passed 19 native cases.
Fourteen additional common cases matched OpenSSL and libsodium.

[Raw paired trials and output fingerprints](poly1305-five-limb-carries.json).

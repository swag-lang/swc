# Poly1305 packed tag output

Poly1305 finalization writes two little-endian words and clears each
contiguous keyed scratch buffer with one wipe. Carry propagation uses
the same 128-bit tag arithmetic.

At 64 bytes, throughput rose from 0.374 to 0.425 GB/s, a paired 1.15×
speedup. The large-record and combined ChaCha20-Poly1305 cases showed
similar rates between Swag builds. OpenSSL 3.5.7 matched all 12 cases.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| poly1305 | 64 | 0 | poly-packed-wipe | chacha-chunks-direct | GB/s | 0.425 | 0.374 | 1.15 [1.11, 1.51] |
| poly1305 | 1024 | 0 | poly-packed-wipe | chacha-chunks-direct | GB/s | 1.26 | 1.26 | 1.01 [0.992, 1.03] |
| poly1305 | 2048 | 0 | poly-packed-wipe | chacha-chunks-direct | GB/s | 1.43 | 1.49 | 1.01 [0.902, 1.05] |
| poly1305 | 2064 | 0 | poly-packed-wipe | chacha-chunks-direct | GB/s | 1.52 | 1.48 | 1.03 [0.982, 1.08] |
| poly1305 | 16384 | 0 | poly-packed-wipe | chacha-chunks-direct | GB/s | 1.86 | 1.84 | 0.999 [0.997, 1.03] |
| poly1305 | 4194304 | 0 | poly-packed-wipe | chacha-chunks-direct | GB/s | 1.88 | 1.86 | 1.01 [0.994, 1.03] |
| chacha20-poly1305 | 64 | 0 | poly-packed-wipe | chacha-chunks-direct | GB/s | 0.125 | 0.122 | 1.03 [0.986, 1.1] |
| chacha20-poly1305 | 1024 | 0 | poly-packed-wipe | chacha-chunks-direct | GB/s | 0.567 | 0.543 | 1.03 [1.01, 1.09] |
| chacha20-poly1305 | 2048 | 0 | poly-packed-wipe | chacha-chunks-direct | GB/s | 0.642 | 0.638 | 0.988 [0.958, 1.01] |
| chacha20-poly1305 | 2064 | 0 | poly-packed-wipe | chacha-chunks-direct | GB/s | 0.616 | 0.588 | 1 [0.862, 1.29] |
| chacha20-poly1305 | 16384 | 0 | poly-packed-wipe | chacha-chunks-direct | GB/s | 0.763 | 0.75 | 1 [0.748, 1.08] |
| chacha20-poly1305 | 4194304 | 0 | poly-packed-wipe | chacha-chunks-direct | GB/s | 0.786 | 0.781 | 1.01 [0.982, 1.22] |

Eighteen focused tests passed in each native Release configuration,
including all-one key carry, partial tails, in-place encryption, and
parallel authenticated encryption.

[Raw trials and output fingerprints](poly1305-tag-stores.json).

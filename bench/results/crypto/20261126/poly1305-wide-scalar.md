# Wide-word scalar Poly1305 fallback

The software block path uses 64-, 64- and 2-bit limbs for at least eight
complete input blocks. The clamped upper key word is a multiple of four,
which lets four full-width multiplications and two bounded 64-bit products
cover each block. The carries use unsigned arithmetic and the path converts
back to the streaming accumulator before returning.

Release was measured with 15 interleaved process-CPU samples per layout on
one EPYC 9V74 core. The input was offset by one byte. The comparison ran
once with normal feature detection and once with the Swag runtime's IFMA
feature masked. OpenSSL 4.1.0 and libsodium 1.0.22 matched all 20 layouts
in each run.

## Host IFMA available

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| poly1305 | 64 | 1 | scalar | base | GB/s | 0.413 | 0.423 | 0.989 [0.955, 1.07] |
| poly1305 | 127 | 1 | scalar | base | GB/s | 0.6 | 0.611 | 0.992 [0.96, 1.07] |
| poly1305 | 128 | 1 | scalar | base | GB/s | 0.683 | 0.671 | 1.02 [0.867, 1.05] |
| poly1305 | 192 | 1 | scalar | base | GB/s | 0.904 | 0.837 | 1.09 [1.06, 1.14] |
| poly1305 | 256 | 1 | scalar | base | GB/s | 1.04 | 0.944 | 1.1 [1.06, 1.14] |
| poly1305 | 319 | 1 | scalar | base | GB/s | 1.07 | 0.93 | 1.13 [1.09, 1.17] |
| poly1305 | 320 | 1 | scalar | base | GB/s | 1.32 | 1.33 | 0.989 [0.962, 1.08] |
| poly1305 | 512 | 1 | scalar | base | GB/s | 1.82 | 1.79 | 1.02 [1, 1.05] |
| poly1305 | 768 | 1 | scalar | base | GB/s | 2.21 | 2.25 | 0.979 [0.931, 1.02] |
| poly1305 | 1023 | 1 | scalar | base | GB/s | 2.4 | 2.4 | 0.993 [0.929, 1.04] |
| poly1305 | 1024 | 1 | scalar | base | GB/s | 2.67 | 2.68 | 1.01 [0.984, 1.08] |
| poly1305 | 4194304 | 1 | scalar | base | GB/s | 4.83 | 4.83 | 1 [0.993, 1.04] |

## Swag IFMA masked

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| poly1305 | 64 | 1 | scalar | base | GB/s | 0.423 | 0.424 | 1.02 [0.983, 1.04] |
| poly1305 | 127 | 1 | scalar | base | GB/s | 0.59 | 0.593 | 0.978 [0.949, 1.03] |
| poly1305 | 128 | 1 | scalar | base | GB/s | 0.67 | 0.668 | 1 [0.967, 1.03] |
| poly1305 | 192 | 1 | scalar | base | GB/s | 0.891 | 0.83 | 1.08 [1.06, 1.11] |
| poly1305 | 256 | 1 | scalar | base | GB/s | 1.06 | 0.934 | 1.14 [1.11, 1.16] |
| poly1305 | 319 | 1 | scalar | base | GB/s | 1.08 | 0.95 | 1.13 [1.11, 1.15] |
| poly1305 | 320 | 1 | scalar | base | GB/s | 1.17 | 1.02 | 1.15 [1.13, 1.23] |
| poly1305 | 512 | 1 | scalar | base | GB/s | 1.43 | 1.19 | 1.21 [1.18, 1.23] |
| poly1305 | 768 | 1 | scalar | base | GB/s | 1.61 | 1.28 | 1.26 [1.22, 1.28] |
| poly1305 | 1023 | 1 | scalar | base | GB/s | 1.62 | 1.3 | 1.25 [1.2, 1.3] |
| poly1305 | 1024 | 1 | scalar | base | GB/s | 1.56 | 1.52 | 1.02 [0.978, 1.1] |
| poly1305 | 4194304 | 1 | scalar | base | GB/s | 2.91 | 2.93 | 0.994 [0.954, 1.03] |

Both feature configurations passed 20 targeted native cases in Release
and Release-safe, with one and four workers. They also passed 1,547
independent key/message layouts in both configurations, comparing a
one-shot and a split update to each reference tag.

[Host raw results](poly1305-wide-scalar-host.json) ·
[Masked raw results](poly1305-wide-scalar-masked.json).

# AVX-512 IFMA for Poly1305

Poly1305 processes pairs of full message blocks with two 44/44/42-bit
accumulators. The IFMA instructions sum low and high 52-bit product halves
separately. A final weighted product combines alternate blocks in message
order. Streaming updates and the existing parallel tile combination both
use the selected path.

The first cutoff experiment found mixed results below 320 bytes. The
selected path starts at 20 complete blocks and uses the existing radix-26
path under that cutoff or when the CPU or operating system lacks the
required feature. The candidate matched the preceding path within the
measured uncertainty at every tested size below 320 bytes.

The test ran 13 interleaved process-CPU samples per layout on one pinned
AMD EPYC 9V74 core. Every layout used a one-byte input offset. OpenSSL 4.1.0
and libsodium 1.0.22 returned the same output for all 36 input layouts.
The table lists selected paired medians. At 4 MiB, OpenSSL measured
12.4 GB/s for Poly1305 and 3.59 GB/s for ChaCha20-Poly1305.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| poly1305 | 64 | 1 | ifma | baseline | GB/s | 0.402 | 0.396 | 1.02 [0.973, 1.08] |
| poly1305 | 319 | 1 | ifma | baseline | GB/s | 0.955 | 0.957 | 0.998 [0.961, 1.04] |
| poly1305 | 320 | 1 | ifma | baseline | GB/s | 1.19 | 1.02 | 1.16 [1.1, 1.18] |
| poly1305 | 512 | 1 | ifma | baseline | GB/s | 1.48 | 1.17 | 1.32 [1.23, 1.35] |
| poly1305 | 1024 | 1 | ifma | baseline | GB/s | 2.09 | 1.53 | 1.36 [1.34, 1.42] |
| poly1305 | 4096 | 1 | ifma | baseline | GB/s | 2.86 | 2.38 | 1.22 [0.946, 1.5] |
| poly1305 | 16384 | 1 | ifma | baseline | GB/s | 3.15 | 2.71 | 1.18 [1.14, 1.26] |
| poly1305 | 4194304 | 1 | ifma | baseline | GB/s | 3.31 | 2.87 | 1.14 [1.12, 1.26] |
| chacha20-poly1305 | 64 | 1 | ifma | baseline | GB/s | 0.127 | 0.129 | 0.984 [0.912, 1.09] |
| chacha20-poly1305 | 319 | 1 | ifma | baseline | GB/s | 0.343 | 0.351 | 1.01 [0.967, 1.09] |
| chacha20-poly1305 | 320 | 1 | ifma | baseline | GB/s | 0.379 | 0.35 | 1.07 [1.03, 1.13] |
| chacha20-poly1305 | 512 | 1 | ifma | baseline | GB/s | 0.535 | 0.48 | 1.11 [1.09, 1.13] |
| chacha20-poly1305 | 1024 | 1 | ifma | baseline | GB/s | 0.687 | 0.609 | 1.12 [0.967, 1.15] |
| chacha20-poly1305 | 4096 | 1 | ifma | baseline | GB/s | 0.869 | 0.813 | 1.07 [1.06, 1.13] |
| chacha20-poly1305 | 16384 | 1 | ifma | baseline | GB/s | 0.922 | 0.888 | 1.03 [0.759, 1.06] |
| chacha20-poly1305 | 4194304 | 1 | ifma | baseline | GB/s | 0.929 | 0.87 | 1.05 [0.883, 1.29] |

The native Release and Release-safe suites passed 20 targeted tests with
one worker and with four workers. Release with IFMA disabled passed the
same suite and preserved the software fallback. An independent corpus
checked 1,547 generated key/message layouts, including maximal and zero
keys, unaligned input, split updates and full parallel tiles. Both native
configurations matched the reference tags for one-shot and split updates.

[Raw timing and output checks](poly1305-ifma.json) ·
[Initial cutoff sweep](poly1305-ifma-cutoff.json).

# Eight-lane AVX2 ChaCha20 experiment

The wide kernel represents eight independent blocks in sixteen named
256-bit vectors. It transposes each group of output words with AVX2
unpacks before applying the keystream. The existing four-block and tail
paths cover the remaining bytes. Both builds use the archived compiler
from the BLAKE3 width experiment and the same historical Core snapshot,
plus the published direct-tail change. The historical Poly1305 code
sets the scope of the AEAD comparison.

On one EPYC 9V74 core, the two builds ran 15 interleaved process-CPU
samples at each input size and offset. The candidate and baseline
matched OpenSSL 4.1.0 and libsodium 1.0.22 in all 28 layouts. The table
shows both offsets around the cutoff and at larger sizes.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| chacha20 | 511 | 0 | avx2 | baseline | GB/s | 0.712 | 0.703 | 0.998 [0.98, 1.03] |
| chacha20 | 511 | 1 | avx2 | baseline | GB/s | 0.724 | 0.723 | 1 [0.991, 1.02] |
| chacha20 | 512 | 0 | avx2 | baseline | GB/s | 1.35 | 1.12 | 1.23 [0.944, 1.29] |
| chacha20 | 512 | 1 | avx2 | baseline | GB/s | 1.3 | 1.08 | 1.24 [1.05, 1.32] |
| chacha20 | 1024 | 0 | avx2 | baseline | GB/s | 1.69 | 1.22 | 1.38 [1.34, 1.45] |
| chacha20 | 1024 | 1 | avx2 | baseline | GB/s | 1.6 | 1.23 | 1.3 [1.14, 1.39] |
| chacha20 | 4096 | 0 | avx2 | baseline | GB/s | 1.93 | 1.32 | 1.47 [1.41, 1.52] |
| chacha20 | 4096 | 1 | avx2 | baseline | GB/s | 1.98 | 1.31 | 1.52 [1.46, 1.53] |
| chacha20 | 16384 | 0 | avx2 | baseline | GB/s | 1.98 | 1.33 | 1.48 [1.33, 1.55] |
| chacha20 | 16384 | 1 | avx2 | baseline | GB/s | 1.55 | 1.32 | 1.35 [1.06, 1.51] |
| chacha20 | 4194304 | 0 | avx2 | baseline | GB/s | 2.03 | 1.34 | 1.52 [1.39, 1.55] |
| chacha20 | 4194304 | 1 | avx2 | baseline | GB/s | 1.99 | 1.34 | 1.5 [1.39, 1.54] |
| chacha20-poly1305 | 511 | 0 | avx2 | baseline | GB/s | 0.369 | 0.36 | 1.01 [0.973, 1.06] |
| chacha20-poly1305 | 511 | 1 | avx2 | baseline | GB/s | 0.376 | 0.377 | 0.996 [0.966, 1.03] |
| chacha20-poly1305 | 512 | 0 | avx2 | baseline | GB/s | 0.51 | 0.469 | 1.11 [1.07, 1.17] |
| chacha20-poly1305 | 512 | 1 | avx2 | baseline | GB/s | 0.512 | 0.47 | 1.09 [0.978, 1.11] |
| chacha20-poly1305 | 1024 | 0 | avx2 | baseline | GB/s | 0.62 | 0.567 | 1.1 [1.01, 1.17] |
| chacha20-poly1305 | 1024 | 1 | avx2 | baseline | GB/s | 0.629 | 0.564 | 1.11 [1.08, 1.15] |
| chacha20-poly1305 | 4096 | 0 | avx2 | baseline | GB/s | 0.887 | 0.721 | 1.23 [1.17, 1.24] |
| chacha20-poly1305 | 4096 | 1 | avx2 | baseline | GB/s | 0.852 | 0.713 | 1.2 [1.05, 1.32] |
| chacha20-poly1305 | 16384 | 0 | avx2 | baseline | GB/s | 0.943 | 0.759 | 1.25 [1.2, 1.35] |
| chacha20-poly1305 | 16384 | 1 | avx2 | baseline | GB/s | 0.949 | 0.763 | 1.24 [1.08, 1.26] |
| chacha20-poly1305 | 4194304 | 0 | avx2 | baseline | GB/s | 0.942 | 0.781 | 1.23 [1.09, 1.26] |
| chacha20-poly1305 | 4194304 | 1 | avx2 | baseline | GB/s | 0.946 | 0.788 | 1.2 [1.01, 1.28] |

At 4 MiB and offset zero, OpenSSL 4.1.0 measured 5.26 GB/s for ChaCha20
and 3.68 GB/s for ChaCha20-Poly1305.

The native Release and Release-safe suites each passed 18 targeted
cases with one and four workers. They exercised exact in-place
operation, unaligned inputs, counter boundaries and native parallel
execution. The experiment uses the compiler's tested local and
pointer-backed wide vectors. General wide-vector ABI and interaction
with opaque YMM bundles remain under compiler validation.

[Raw paired timings and output fingerprints](chacha20-native-width.json) ·
[Reproduction steps and archived consumer patch](../../../workloads/crypto/native-width/README.md).

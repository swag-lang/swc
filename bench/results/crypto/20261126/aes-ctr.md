# Batched AES-CTR with a 128-bit counter

AES-CTR shares the batched AES rounds and keeps full-width counter carry.
The 15 native AES-CTR and GCM tests passed in Release, Release-safe, and under
QEMU with AES and PCLMUL masked. The added fixture crosses the low 64-bit carry
with an unaligned tail and exact in-place buffers. OpenSSL matched 112 further
unaligned CTR and GCM cases, and the P-256 signing comparator still passed.

The common workload used 11 paired process CPU-time trials on AMD EPYC 9V74 CPU 2.
GCM at 1 MiB stayed at 3.27 GB/s and served as a shared-kernel control.

| Bytes | CTR before GB/s | CTR after GB/s | OpenSSL GB/s | Speedup (95% CI) |
| ---: | ---: | ---: | ---: | ---: |
| 64 | 0.133 | 0.316 | 0.265 | 2.4 [2, 2.73] |
| 4096 | 0.258 | 5.19 | 5.61 | 20.1 [19.9, 20.8] |
| 65536 | 0.262 | 6.64 | 7.94 | 25.2 [24.6, 25.9] |
| 1048576 | 0.261 | 6.61 | 8.02 | 25.6 [24.4, 26] |

[Raw CTR and GCM trials](aes-ctr.json).

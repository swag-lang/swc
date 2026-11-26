# Interleaved AES-GCM counter encryption and GHASH

The serial hardware path alternates AES encryption rounds with carry-less
products over the previous ciphertext. Named SIMD locals hold the
dependency chains. The serial path applies from 128 bytes. Large records
still use the parallel path with multiple configured workers.

At 1 MiB, the native Release process-clock workload measured 3.22 GB/s
before and 3.75 GB/s after, with a paired speedup of 1.19× [1.14, 1.22].
OpenSSL 3.5.7 reached 10.1 GB/s with native hardware dispatch and 4.32
GB/s with VAES and VPCLMUL disabled.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| aes-256-gcm | 64 | 0 | interleaved | OpenSSL | GB/s | 0.194 | 0.183 | 1.07 [1.05, 1.1] |
| aes-256-gcm | 64 | 0 | interleaved | current | GB/s | 0.194 | 0.195 | 0.996 [0.935, 1.18] |
| aes-256-gcm | 128 | 0 | interleaved | OpenSSL | GB/s | 0.419 | 0.36 | 1.17 [0.791, 1.18] |
| aes-256-gcm | 128 | 0 | interleaved | current | GB/s | 0.419 | 0.384 | 1.09 [0.851, 1.27] |
| aes-256-gcm | 256 | 0 | interleaved | OpenSSL | GB/s | 0.743 | 0.684 | 1.09 [0.977, 1.14] |
| aes-256-gcm | 256 | 0 | interleaved | current | GB/s | 0.743 | 0.675 | 1.11 [1.03, 1.33] |
| aes-256-gcm | 4096 | 0 | interleaved | OpenSSL | GB/s | 3.08 | 5.07 | 0.609 [0.592, 0.64] |
| aes-256-gcm | 4096 | 0 | interleaved | current | GB/s | 3.08 | 2.61 | 1.19 [1.15, 1.23] |
| aes-256-gcm | 65536 | 0 | interleaved | OpenSSL | GB/s | 3.8 | 9.8 | 0.386 [0.372, 0.417] |
| aes-256-gcm | 65536 | 0 | interleaved | current | GB/s | 3.8 | 3.23 | 1.18 [1.14, 1.2] |
| aes-256-gcm | 1048576 | 0 | interleaved | OpenSSL | GB/s | 3.75 | 10.1 | 0.378 [0.366, 0.387] |
| aes-256-gcm | 1048576 | 0 | interleaved | current | GB/s | 3.75 | 3.22 | 1.19 [1.14, 1.22] |

External verification matched 64 one-worker offsets and sizes plus 10
cases around the four-worker cutoff. Each native Release configuration
passed 37 focused cases on the host and with AES disabled, PCLMUL
disabled, and both disabled under QEMU.

[Raw paired trials](aes-gcm-interleaved.json) · [Serial verification](aes-gcm-interleaved-verification.json) · [Parallel verification](aes-gcm-interleaved-parallel.json).

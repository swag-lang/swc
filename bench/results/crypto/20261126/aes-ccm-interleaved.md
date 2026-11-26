# Interleaved AES-CCM authentication and counter rounds

The hardware path schedules CBC-MAC and the following CTR block with
the same expanded key. It retains the tag counter and authenticates a
partial plaintext tail before writing that tail in place.

At 1 MiB, throughput increased from 0.744 to 0.843 GB/s, a paired 1.12×
[1.09, 1.16]. OpenSSL 3.5.7 reached about 1.0 GB/s in the same workload.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| aes-256-ccm | 64 | 0 | interleaved | OpenSSL | GB/s | 0.185 | 0.267 | 0.698 [0.617, 0.723] |
| aes-256-ccm | 64 | 0 | interleaved | separate | GB/s | 0.185 | 0.167 | 1.09 [1.01, 1.26] |
| aes-256-ccm | 4096 | 0 | interleaved | OpenSSL | GB/s | 0.793 | 0.954 | 0.831 [0.798, 0.858] |
| aes-256-ccm | 4096 | 0 | interleaved | separate | GB/s | 0.793 | 0.716 | 1.12 [1.03, 1.23] |
| aes-256-ccm | 65536 | 0 | interleaved | OpenSSL | GB/s | 0.825 | 1 | 0.823 [0.747, 0.854] |
| aes-256-ccm | 65536 | 0 | interleaved | separate | GB/s | 0.825 | 0.746 | 1.11 [1.01, 1.13] |
| aes-256-ccm | 1048576 | 0 | interleaved | OpenSSL | GB/s | 0.843 | 0.99 | 0.848 [0.825, 0.872] |
| aes-256-ccm | 1048576 | 0 | interleaved | separate | GB/s | 0.843 | 0.744 | 1.12 [1.09, 1.16] |

Native Release and Release-safe each passed five focused CCM cases,
including the hardware-masked runs. External validation matched 56
one-worker and 10 four-worker cases around the parallel cutoff.

[Raw paired trials](aes-ccm-interleaved.json) · [One-worker verification](aes-ccm-interleaved-verification.json) · [Parallel verification](aes-ccm-interleaved-parallel.json).

# Cumulative AES comparison with OpenSSL 4.1

Swag AES-256-CTR reached 7.80 GB/s at 1 MiB versus 8.13 GB/s for
OpenSSL 4.1.0. CCM, CMAC and SIV delivered 85–86% of OpenSSL bulk
throughput. The largest bulk gaps were GCM, GCM associated data and XTS.
At 64 bytes Swag SIV reached 0.0822 GB/s, 1.97× the OpenSSL result.
Swag key wrapping and unwrapping were 4.65× to 7.28× faster at that size.

## Bulk modes

All rates are in GB/s. The GCM, CCM and SIV data rows time sealing with
associated data and emit the complete authentication tag. GCM associated
data uses an empty plaintext and counts only the associated-data bytes.

| AES-256 operation | Swag at 64 B | OpenSSL at 64 B | Swag at 1 MiB | OpenSSL at 1 MiB | Swag/OpenSSL at 1 MiB (95% CI) |
| --- | ---: | ---: | ---: | ---: | ---: |
| CTR | 0.46 | 0.428 | 7.8 | 8.13 | 0.973 [0.952, 0.989] |
| GCM seal | 0.195 | 0.224 | 3.9 | 10.2 | 0.383 [0.377, 0.391] |
| GCM associated data only | 0.219 | 0.267 | 6.29 | 23 | 0.272 [0.269, 0.279] |
| CCM seal | 0.185 | 0.281 | 0.848 | 1.01 | 0.846 [0.837, 0.902] |
| CMAC | 0.173 | 0.341 | 0.856 | 1.01 | 0.847 [0.836, 0.851] |
| SIV seal | 0.0822 | 0.0423 | 0.764 | 0.892 | 0.857 [0.847, 0.866] |
| XTS encrypt | 0.306 | 0.321 | 5.85 | 13.5 | 0.433 [0.422, 0.442] |
| XTS decrypt | 0.295 | 0.311 | 5.83 | 13.9 | 0.422 [0.418, 0.458] |

## Key wrapping

The harness times both directions and counts unwrapped key bytes.
For an unwrap trial it builds the wrapped fixture before timing.
The OpenSSL 4.1 EVP key-wrap provider uses its generic AES block
operations. [OpenSSL provider source](https://github.com/openssl/openssl/blob/openssl-4.1.0/providers/implementations/ciphers/cipher_aes_wrp.c)

| AES-256 operation | Swag at 64 B | OpenSSL at 64 B | Swag at 4 KiB | OpenSSL at 4 KiB | Swag/OpenSSL at 4 KiB (95% CI) |
| --- | ---: | ---: | ---: | ---: | ---: |
| KW wrap | 0.0518 | 0.0106 | 0.0573 | 0.0107 | 5.35 [4.88, 5.49] |
| KW unwrap | 0.0529 | 0.00722 | 0.0609 | 0.00733 | 8.37 [7.78, 8.63] |
| KWP wrap | 0.0482 | 0.0104 | 0.0552 | 0.0106 | 5.18 [5.11, 5.25] |
| KWP unwrap | 0.0519 | 0.00724 | 0.061 | 0.00743 | 8.23 [7.9, 8.55] |

## Method and verification

The Swag executable uses the library and benchmark from `80dbf6db83`
and the combined x64 Release compiler. The reference rebuild uses the
same benchmark source compiled against OpenSSL 4.1.0. Each workload
uses one worker pinned to CPU 2 on the AMD EPYC 9V74. Eleven interleaved
trials targeted 16 ms of process CPU time per input and implementation.
The bulk panel used 64 B, 4 KiB, 64 KiB and 1 MiB. The key-wrap panel
used 16 B, 64 B, 256 B and 4 KiB.

The harness checked full outputs before and after timed trials.
The separate verification compared 672 size-and-offset combinations,
including XTS ciphertext stealing and the single-block KWP boundary.
The combined compiler also passed all 39 focused AES cases in Release
and Release-safe, on the host and under QEMU with AES and PCLMUL disabled.
[Workload and build instructions](../../../workloads/crypto/README.md)

## Historical GCM replay

The saved initial Release executable from `d9bfeae85f` matched the same
complete ciphertexts and tags in a separate paired run. At 1 MiB,
throughput rose from 0.000560 GB/s to 3.92 GB/s, about 7000×. OpenSSL
reached 10.4 GB/s in this run. This replay compares the historical and
current executables and includes their respective compiler builds.

[Bulk trials](aes-cumulative-bulk.json) · [Key-wrap trials](aes-cumulative-wrap.json) · [Historical GCM trials](aes-cumulative-gcm-history.json)

[Bulk verification](aes-cumulative-bulk-verification.json) · [KW verification](aes-cumulative-kw-verification.json) · [KWP verification](aes-cumulative-kwp-verification.json) · [Historical GCM verification](aes-cumulative-gcm-history-verification.json)

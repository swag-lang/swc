# Portable GHASH with wide integer products

The portable field product computes sparse residues with full-width
integer multiplication. It separates one nibble during the product to
bound the terms in each column, then restores its contribution using
the same fixed schedule.

The paired process CPU-time workload disabled PCLMUL dispatch while
leaving AES hardware available. The OpenSSL reference also had carry-less
multiplication disabled. At 1 MiB, AAD-only GHASH rose from 0.218 to
0.320 GB/s and full GCM from 0.214 to 0.308 GB/s.

| Algorithm | Bytes | Offset | Swag build | Comparator | Unit | Swag rate | Comparator rate | Paired speed ratio (95% CI) |
| --- | ---: | ---: | --- | --- | --- | ---: | ---: | ---: |
| aes-256-gcm-aad | 64 | 0 | wide-mul | OpenSSL | GB/s | 0.114 | 0.132 | 0.872 [0.809, 0.928] |
| aes-256-gcm-aad | 64 | 0 | wide-mul | scalar-32 | GB/s | 0.114 | 0.096 | 1.2 [1.11, 1.28] |
| aes-256-gcm-aad | 4096 | 0 | wide-mul | OpenSSL | GB/s | 0.297 | 0.53 | 0.568 [0.535, 0.586] |
| aes-256-gcm-aad | 4096 | 0 | wide-mul | scalar-32 | GB/s | 0.297 | 0.202 | 1.47 [1.42, 1.52] |
| aes-256-gcm-aad | 65536 | 0 | wide-mul | OpenSSL | GB/s | 0.313 | 0.573 | 0.543 [0.505, 0.559] |
| aes-256-gcm-aad | 65536 | 0 | wide-mul | scalar-32 | GB/s | 0.313 | 0.219 | 1.45 [1.42, 1.5] |
| aes-256-gcm-aad | 1048576 | 0 | wide-mul | OpenSSL | GB/s | 0.32 | 0.576 | 0.556 [0.539, 0.563] |
| aes-256-gcm-aad | 1048576 | 0 | wide-mul | scalar-32 | GB/s | 0.32 | 0.218 | 1.46 [1.45, 1.48] |
| aes-256-gcm | 64 | 0 | wide-mul | OpenSSL | GB/s | 0.103 | 0.116 | 0.891 [0.86, 0.897] |
| aes-256-gcm | 64 | 0 | wide-mul | scalar-32 | GB/s | 0.103 | 0.083 | 1.24 [1.19, 1.28] |
| aes-256-gcm | 4096 | 0 | wide-mul | OpenSSL | GB/s | 0.3 | 0.515 | 0.584 [0.574, 0.708] |
| aes-256-gcm | 4096 | 0 | wide-mul | scalar-32 | GB/s | 0.3 | 0.206 | 1.44 [1.42, 1.5] |
| aes-256-gcm | 65536 | 0 | wide-mul | OpenSSL | GB/s | 0.311 | 0.546 | 0.569 [0.562, 0.579] |
| aes-256-gcm | 65536 | 0 | wide-mul | scalar-32 | GB/s | 0.311 | 0.215 | 1.45 [1.42, 1.46] |
| aes-256-gcm | 1048576 | 0 | wide-mul | OpenSSL | GB/s | 0.308 | 0.536 | 0.567 [0.524, 0.665] |
| aes-256-gcm | 1048576 | 0 | wide-mul | scalar-32 | GB/s | 0.308 | 0.214 | 1.43 [1.27, 1.45] |

An independent integer model matched 50,064 polynomial products,
including all-one carries. The external sweep matched 48 unaligned
AAD-only inputs and 48 unaligned GCM inputs. Nine focused cases passed
both native Release configurations on the host, in QEMU with PCLMUL
disabled, and in QEMU with both AES and PCLMUL disabled.

[Raw paired trials](ghash-wide-integer.json) · [External verification](ghash-wide-integer-verification.json).
